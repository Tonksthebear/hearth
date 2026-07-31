require "base64"
require "json"
require "open3"
require "pathname"

module Acp
  class Connection
    class Error < StandardError; end
    class ConfigurationError < Error; end
    class ProcessError < Error; end
    class ProtocolError < Error; end
    class BackpressureError < ProtocolError; end
    class TimeoutError < Error; end
    class Unsupported < Error; end
    class RequestError < Error
      attr_reader :code, :data

      def initialize(error)
        @code = error["code"]
        @data = error["data"]
        super(error["message"].presence || "ACP request failed")
      end
    end

    PROTOCOL_VERSION = 1
    DEFAULT_TIMEOUT = 60
    DEFAULT_MAX_LINE_BYTES = 4 * 1024 * 1024
    DEFAULT_QUEUE_SIZE = 128
    DEFAULT_QUEUE_TIMEOUT = 0.25
    DEFAULT_TERMINATION_GRACE = 1
    STDERR_LIMIT = 16 * 1024
    STOP_WRITER = Object.new.freeze

    attr_reader :agent_capabilities, :agent_info, :auth_methods, :default_auth_method_id,
      :dropped_event_count, :mcp_servers, :pid

    def initialize(argv:, cwd:, environment: {}, mcp_servers: [], timeout: DEFAULT_TIMEOUT,
      max_line_bytes: DEFAULT_MAX_LINE_BYTES, queue_size: DEFAULT_QUEUE_SIZE,
      queue_timeout: DEFAULT_QUEUE_TIMEOUT, termination_grace: DEFAULT_TERMINATION_GRACE,
      on_fatal: ->(_error) { })
      raise ConfigurationError, "agent argv is required" if argv.blank?
      raise ConfigurationError, "agent argv must contain only strings" unless argv.all? { |argument| argument.is_a?(String) }
      raise ConfigurationError, "cwd must be absolute" unless Pathname.new(cwd).absolute?
      raise ConfigurationError, "environment must contain string names and values" unless
        environment.all? { |name, value| name.is_a?(String) && value.is_a?(String) }

      @argv = argv.dup.freeze
      @cwd = cwd
      @environment = environment.dup.freeze
      @mcp_servers = normalize_mcp_servers(mcp_servers)
      @timeout = Float(timeout)
      @max_line_bytes = Integer(max_line_bytes)
      @queue_timeout = Float(queue_timeout)
      @termination_grace = Float(termination_grace)
      @on_fatal = on_fatal
      @outbound = SizedQueue.new(Integer(queue_size))
      @events = SizedQueue.new(Integer(queue_size))
      @pending = {}
      @pending_mutex = Mutex.new
      @events_mutex = Mutex.new
      @state_mutex = Mutex.new
      @stderr_mutex = Mutex.new
      @finalize_mutex = Mutex.new
      @stderr = +""
      @next_id = 0
      @dropped_event_count = 0
      @stopping = false
      @finalized = false
    end

    def start
      @state_mutex.synchronize do
        return self if @wait_thread&.alive?

        @stdin, @stdout, @stderr_io, @wait_thread = Open3.popen3(
          @environment,
          *@argv,
          chdir: @cwd,
          pgroup: true,
          unsetenv_others: true
        )
        @pid = @wait_thread.pid
        @stdout_thread = Thread.new { read_stdout }
        @stderr_thread = Thread.new { read_stderr }
        @writer_thread = Thread.new { write_outbound }
      end
      self
    rescue SystemCallError => error
      raise ProcessError, "Could not start ACP agent (#{error.class.name})"
    end

    def initialize_connection
      result = request("initialize", {
        protocolVersion: PROTOCOL_VERSION,
        clientCapabilities: {},
        clientInfo: {
          name: "hearth",
          title: "Hearth ACP Runtime",
          version: "1"
        }
      })
      unless result["protocolVersion"] == PROTOCOL_VERSION
        raise ProtocolError, "agent selected unsupported ACP version #{result['protocolVersion'].inspect}"
      end

      @agent_capabilities = result.fetch("agentCapabilities", {})
      @agent_info = result["agentInfo"] || {}
      @auth_methods = result.fetch("authMethods", [])
      @default_auth_method_id = result.dig("_meta", "defaultAuthMethodId")
      result
    rescue KeyError => error
      raise ProtocolError, "invalid initialize result: #{error.message}"
    end

    def authentication_method_id(preferred = nil)
      method_id = preferred || default_auth_method_id || (auth_methods&.one? && auth_methods.first["id"])
      return unless method_id
      raise Unsupported, "authentication method is not advertised" unless
        auth_methods.any? { |method| method["id"] == method_id }

      method_id
    end

    def authenticate(method_id)
      raise Unsupported, "authentication method is not advertised" unless
        auth_methods.any? { |method| method["id"] == method_id }

      request("authenticate", { methodId: method_id })
    end

    def new_session
      result = request("session/new", session_params)
      @session_id = valid_session_id!(result)
      result
    end

    def configure_mcp_servers!(servers)
      raise ConfigurationError, "MCP configuration is immutable after session selection" if @session_id

      @mcp_servers = normalize_mcp_servers(servers)
      self
    end

    def inspect = "#<#{self.class.name} pid=#{pid.inspect} [MCP CREDENTIALS REDACTED]>"

    def resume(session_id)
      require_capability!("resume")
      @session_id = validate_session_id!(session_id)
      request("session/resume", session_params.merge(sessionId: @session_id))
    end

    def load(session_id)
      raise Unsupported, "agent does not advertise session/load" unless agent_capabilities["loadSession"]

      @session_id = validate_session_id!(session_id)
      request("session/load", session_params.merge(sessionId: @session_id))
    end

    def list_sessions(cwd: nil, cursor: nil)
      raise Unsupported, "agent does not advertise session/list" unless
        agent_capabilities.dig("sessionCapabilities", "list")

      request("session/list", { cwd: cwd, cursor: cursor }.compact)
    end

    def prompt(content)
      require_session!
      validate_content!(content)
      request("session/prompt", { sessionId: @session_id, prompt: content })
    end

    def cancel
      require_session!
      notify("session/cancel", { sessionId: @session_id })
    end

    def close_session
      require_session!
      require_capability!("close")
      request("session/close", { sessionId: @session_id })
    end

    def text_resource(path)
      {
        type: "resource",
        resource: {
          uri: "file://#{File.expand_path(path)}",
          mimeType: "text/plain",
          text: File.read(path)
        }
      }
    end

    def image(path)
      {
        type: "image",
        mimeType: "image/png",
        data: Base64.strict_encode64(File.binread(path)),
        uri: "file://#{File.expand_path(path)}"
      }
    end

    def next_event(timeout: @timeout)
      pop_with_deadline(@events, timeout)
    end

    def drain_events
      events = []
      loop { events << @events.pop(true) }
    rescue ThreadError
      events
    end

    def stderr
      @stderr_mutex.synchronize { @stderr.dup }
    end

    def running?
      @wait_thread&.alive? && !failure
    end

    def failure
      @state_mutex.synchronize { @failure }
    end

    def stop
      finalize
      nil
    end

    private
      def request(method, params)
        id = next_id
        response_queue = SizedQueue.new(1)
        @pending_mutex.synchronize { @pending[id] = response_queue }
        enqueue_outbound(jsonrpc: "2.0", id: id, method: method, params: params)

        response = pop_with_deadline(response_queue, @timeout)
        raise response if response.is_a?(Exception)
        raise RequestError, response["error"] if response["error"]

        response["result"]
      rescue TimeoutError
        error = TimeoutError.new("ACP request #{method} timed out after #{@timeout} seconds")
        fail_connection(error)
        raise error
      ensure
        @pending_mutex.synchronize { @pending.delete(id) } if id
      end

      def notify(method, params)
        enqueue_outbound(jsonrpc: "2.0", method: method, params: params)
      end

      def next_id
        @state_mutex.synchronize { @next_id += 1 }
      end

      def pop_with_deadline(queue, timeout)
        value = queue.pop(timeout: Float(timeout))
        return value if value

        raise(failure || TimeoutError.new("ACP queue wait timed out"))
      end

      def enqueue_outbound(message)
        raise(failure || ProcessError.new("agent is not running")) unless @wait_thread&.alive?

        payload = JSON.generate(message)
        raise ProtocolError, "outgoing ACP frame is too large" if payload.bytesize > @max_line_bytes

        bounded_push(@outbound, payload)
      rescue BackpressureError, ProtocolError => error
        fail_connection(error)
        raise
      end

      def bounded_push(queue, value)
        return if queue.push(value, timeout: @queue_timeout)

        raise BackpressureError, "ACP queue remained saturated"
      end

      def write_outbound
        loop do
          payload = @outbound.pop
          break if payload.equal?(STOP_WRITER)

          @stdin.write(payload)
          @stdin.write("\n")
          @stdin.flush
        end
      rescue Errno::EPIPE, IOError => error
        fail_connection(ProcessError.new("agent stdin closed (#{error.class.name})")) unless stopping?
      end

      def read_stdout
        loop do
          line = @stdout.gets(@max_line_bytes + 1)
          break unless line
          unless line.end_with?("\n")
            message = line.bytesize > @max_line_bytes ? "ACP frame exceeds #{@max_line_bytes} bytes" : "partial ACP frame before EOF"
            raise ProtocolError, message
          end
          raise ProtocolError, "ACP frame is not valid UTF-8" unless line.force_encoding(Encoding::UTF_8).valid_encoding?

          dispatch(JSON.parse(line))
        end
        fail_connection(ProcessError.new("agent exited before transport shutdown")) unless stopping?
      rescue JSON::ParserError
        fail_connection(ProtocolError.new("invalid ACP JSON"))
        drain_to_eof(@stdout)
      rescue ProtocolError, IOError => error
        fail_connection(error) unless stopping?
        drain_to_eof(@stdout)
      end

      def read_stderr
        while (chunk = @stderr_io.readpartial(4096))
          @stderr_mutex.synchronize do
            @stderr << chunk
            @stderr = @stderr.byteslice(-STDERR_LIMIT, STDERR_LIMIT) if @stderr.bytesize > STDERR_LIMIT
          end
        end
      rescue EOFError, IOError
        nil
      end

      def dispatch(message)
        unless message.is_a?(Hash) && message["jsonrpc"] == "2.0"
          raise ProtocolError, "invalid JSON-RPC envelope"
        end

        if message["method"]
          handle_agent_message(message)
        elsif message.key?("id")
          queue = @pending_mutex.synchronize { @pending.delete(message["id"]) }
          raise ProtocolError, "response for unknown or duplicate id #{message['id'].inspect}" unless queue

          queue.push(message, true)
        else
          raise ProtocolError, "JSON-RPC message has no method or id"
        end
      rescue ThreadError
        raise ProtocolError, "duplicate response for completed request"
      end

      def handle_agent_message(message)
        if message.key?("id")
          handle_agent_request(message)
        else
          retain_event(message)
        end
      end

      def retain_event(message)
        @events_mutex.synchronize do
          loop do
            @events.push(message, true)
            break
          rescue ThreadError
            begin
              @events.pop(true)
              @dropped_event_count += 1
            rescue ThreadError
              next
            end
          end
        end
      end

      def handle_agent_request(message)
        result = if message["method"] == "session/request_permission"
          option = message.dig("params", "options")&.find { |candidate| candidate["kind"] == "reject_once" }
          option ? { outcome: { outcome: "selected", optionId: option.fetch("optionId") } } : { outcome: { outcome: "cancelled" } }
        end

        if result
          enqueue_outbound(jsonrpc: "2.0", id: message["id"], result: result)
        else
          enqueue_outbound(jsonrpc: "2.0", id: message["id"], error: {
            code: -32601,
            message: "Method not supported by Hearth"
          })
        end
      end

      def session_params
        { cwd: @cwd, mcpServers: @mcp_servers }
      end

      def valid_session_id!(result)
        validate_session_id!(result["sessionId"])
      rescue NoMethodError
        raise ProtocolError, "session/new did not return a result object"
      end

      def validate_session_id!(session_id)
        raise ProtocolError, "ACP session id is missing" unless session_id.is_a?(String) && session_id.present?

        session_id
      end

      def require_session!
        raise ProtocolError, "session has not been selected" unless @session_id
      end

      def require_capability!(name)
        raise Unsupported, "agent does not advertise session/#{name}" unless
          agent_capabilities.dig("sessionCapabilities", name)
      end

      def validate_content!(content)
        raise ProtocolError, "prompt content must be an array" unless content.is_a?(Array)

        prompt_capabilities = agent_capabilities.fetch("promptCapabilities", {})
        content.each do |block|
          case block[:type] || block["type"]
          when "image"
            raise Unsupported, "agent does not advertise image prompts" unless prompt_capabilities["image"]
          when "resource"
            raise Unsupported, "agent does not advertise embedded resources" unless prompt_capabilities["embeddedContext"]
          end
        end
      end

      def normalize_mcp_servers(servers)
        normalized = JSON.parse(JSON.generate(servers))
        raise ConfigurationError, "mcp_servers must be a collection" unless normalized.is_a?(Array)

        deep_freeze(normalized)
      rescue JSON::GeneratorError, TypeError => error
        raise ConfigurationError, "mcp_servers are not JSON-compatible: #{error.message}"
      end

      def deep_freeze(value)
        case value
        when Hash
          value.each { |key, item| key.freeze; deep_freeze(item) }
        when Array
          value.each { |item| deep_freeze(item) }
        else
          value.freeze
        end
        value.freeze
      end

      def fail_connection(error)
        callback = nil
        @state_mutex.synchronize do
          return if @failure || @stopping

          @failure = error
          callback = @on_fatal
        end
        reject_pending(error)
        callback.call(error)
        @cleanup_thread ||= Thread.new { finalize }
      rescue StandardError
        @cleanup_thread ||= Thread.new { finalize }
      end

      def reject_pending(error)
        pending = @pending_mutex.synchronize do
          queues = @pending.values
          @pending.clear
          queues
        end
        pending.each { |queue| queue.push(error, true) rescue nil }
      end

      def finalize
        @finalize_mutex.synchronize do
          return if @finalized

          @state_mutex.synchronize { @stopping = true }
          reject_pending(ProcessError.new("ACP connection stopped"))
          @outbound.push(STOP_WRITER, true) rescue nil
          @stdin&.close unless @stdin&.closed?
          terminate_process_group
          @writer_thread&.join(@termination_grace)
          [ @stdout_thread, @stderr_thread ].compact.each do |thread|
            thread.join(@termination_grace * 2) unless thread == Thread.current
          end
          [ @stdout, @stderr_io ].compact.each { |io| io.close unless io.closed? }
          @finalized = true
        end
      end

      def terminate_process_group
        return unless @wait_thread

        signal_process_group("TERM")
        @wait_thread.join(@termination_grace)
        # The leader may exit on TERM while a descendant retains the process
        # group and pipe writers. Always escalate the owned group after grace.
        signal_process_group("KILL")
        @wait_thread.join(@termination_grace) if @wait_thread.alive?
        @wait_thread.join unless @wait_thread.alive?
      rescue Errno::ECHILD, Errno::ESRCH
        nil
      end

      def signal_process_group(signal)
        Process.kill(signal, -@pid)
      rescue Errno::EPERM
        Process.kill(signal, @pid)
      rescue Errno::ESRCH
        nil
      end

      def drain_to_eof(io)
        io.readpartial(4096) while true
      rescue EOFError, IOError
        nil
      end

      def stopping?
        @state_mutex.synchronize { @stopping }
      end

      def monotonic_now
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
  end
end
