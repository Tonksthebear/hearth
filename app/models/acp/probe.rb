require "base64"
require "json"
require "open3"
require "pathname"
require "timeout"

module Acp
  class Probe
    class Error < StandardError; end
    class ProtocolError < Error; end
    class RequestError < Error
      attr_reader :code, :data

      def initialize(error)
        @code = error["code"]
        @data = error["data"]
        super(error["message"] || "ACP request failed")
      end
    end
    class Unsupported < Error; end

    DEFAULT_TIMEOUT = 15
    DEFAULT_MAX_LINE_BYTES = 4 * 1024 * 1024
    STDERR_LIMIT = 16 * 1024

    attr_reader :agent_capabilities, :agent_info, :auth_methods, :pid, :updates

    def initialize(argv:, cwd:, mcp_url: nil, stdio_proxy_path: nil, timeout: DEFAULT_TIMEOUT, max_line_bytes: DEFAULT_MAX_LINE_BYTES)
      raise ArgumentError, "agent argv is required" if argv.empty?
      raise ArgumentError, "cwd must be absolute" unless Pathname.new(cwd).absolute?

      @argv = argv
      @cwd = cwd
      @mcp_url = mcp_url || ENV.fetch("HEARTH_MCP_URL", "http://127.0.0.1:3000/mcp")
      @stdio_proxy_path = File.expand_path(stdio_proxy_path || "../../../bin/hearth-mcp-spike-proxy", __dir__)
      @timeout = timeout
      @max_line_bytes = max_line_bytes
      @pending = {}
      @pending_mutex = Mutex.new
      @write_mutex = Mutex.new
      @updates = []
      @errors = Queue.new
      @stderr = +""
      @next_id = 0
    end

    def start
      return self if running?

      @stdin, @stdout, @stderr_io, @wait_thread = Open3.popen3(*@argv, chdir: @cwd, pgroup: true)
      @pid = @wait_thread.pid
      @stdout_thread = Thread.new { read_stdout }
      @stderr_thread = Thread.new { read_stderr }
      self
    end

    def initialize_connection
      result = request("initialize", {
        protocolVersion: 1,
        clientCapabilities: {},
        clientInfo: {
          name: "hearth-acp-spike",
          title: "Hearth ACP Conformance Spike",
          version: "0.1.0"
        }
      })

      raise ProtocolError, "agent selected unsupported ACP version #{result["protocolVersion"].inspect}" unless result["protocolVersion"] == 1

      @agent_capabilities = result.fetch("agentCapabilities", {})
      @agent_info = result["agentInfo"]
      @auth_methods = result.fetch("authMethods", [])
      result
    end

    def authenticate(method_id)
      advertised = auth_methods.find { |method| method["id"] == method_id }
      raise Unsupported, "authentication method is not advertised" unless advertised

      request("authenticate", { methodId: method_id })
    end

    def new_session
      result = request("session/new", session_params)
      @session_id = result.fetch("sessionId")
      result
    end

    def prompt(content)
      raise ProtocolError, "session has not been created" unless @session_id

      validate_content!(content)
      request("session/prompt", { sessionId: @session_id, prompt: content })
    end

    def cancel
      raise ProtocolError, "session has not been created" unless @session_id

      notify("session/cancel", { sessionId: @session_id })
    end

    def close
      require_session_capability!("close")
      request("session/close", { sessionId: @session_id })
    end

    def resume
      require_session_capability!("resume")
      request("session/resume", session_params.merge(sessionId: @session_id))
    end

    def load
      raise Unsupported, "agent does not advertise session/load" unless agent_capabilities["loadSession"]

      request("session/load", session_params.merge(sessionId: @session_id))
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

    def mcp_servers
      if agent_capabilities.dig("mcpCapabilities", "http")
        [ { type: "http", name: "hearth-spike", url: @mcp_url, headers: [] } ]
      else
        [ {
          name: "hearth-spike",
          command: @stdio_proxy_path,
          args: [],
          env: [ { name: "HEARTH_MCP_URL", value: @mcp_url } ]
        } ]
      end
    end

    def stderr
      @stderr.dup
    end

    def running?
      @wait_thread&.alive?
    end

    def stop
      @stdin&.close unless @stdin&.closed?
      terminate_process
      [ @stdout, @stderr_io ].compact.each { |io| io.close unless io.closed? }
      [ @stdout_thread, @stderr_thread ].compact.each { |thread| thread.join(0.5) }
      nil
    end

    private
      def request(method, params)
        id = next_id
        response_queue = Queue.new
        @pending_mutex.synchronize { @pending[id] = response_queue }
        write_message(jsonrpc: "2.0", id: id, method: method, params: params)

        response = wait_for(response_queue)
        raise RequestError, response["error"] if response["error"]

        response["result"]
      ensure
        @pending_mutex.synchronize { @pending.delete(id) } if id
      end

      def notify(method, params)
        write_message(jsonrpc: "2.0", method: method, params: params)
      end

      def next_id
        @next_id += 1
      end

      def wait_for(queue)
        Timeout.timeout(@timeout) do
          loop do
            raise @errors.pop unless @errors.empty?
            return queue.pop(true) unless queue.empty?
            raise Error, "agent exited before responding" if @wait_thread && !@wait_thread.alive?
            sleep 0.01
          end
        end
      rescue Timeout::Error
        raise Error, "ACP request timed out after #{@timeout} seconds"
      end

      def write_message(message)
        raise Error, "agent is not running" unless running?

        payload = JSON.generate(message)
        raise ProtocolError, "outgoing ACP frame is too large" if payload.bytesize > @max_line_bytes

        @write_mutex.synchronize do
          @stdin.write(payload)
          @stdin.write("\n")
          @stdin.flush
        end
      rescue Errno::EPIPE, IOError => error
        raise Error, "agent pipe closed: #{error.message}"
      end

      def read_stdout
        loop do
          line = @stdout.gets(@max_line_bytes + 1)
          break unless line
          raise ProtocolError, "ACP frame exceeds #{@max_line_bytes} bytes" unless line.end_with?("\n")

          dispatch(JSON.parse(line))
        end
      rescue JSON::ParserError => error
        @errors << ProtocolError.new("invalid ACP JSON: #{error.message}")
      rescue Error, IOError => error
        @errors << error unless @stdout.closed?
      end

      def read_stderr
        while (chunk = @stderr_io.readpartial(4096))
          remaining = STDERR_LIMIT - @stderr.bytesize
          @stderr << chunk.byteslice(0, remaining) if remaining.positive?
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
          queue = @pending_mutex.synchronize { @pending[message["id"]] }
          raise ProtocolError, "response for unknown id #{message["id"].inspect}" unless queue
          queue << message
        else
          raise ProtocolError, "JSON-RPC message has no method or id"
        end
      end

      def handle_agent_message(message)
        if message["id"]
          handle_agent_request(message)
        elsif message["method"] == "session/update"
          @updates << message.fetch("params")
        end
      end

      def handle_agent_request(message)
        if message["method"] == "session/request_permission"
          option = message.dig("params", "options")&.find { |candidate| candidate["kind"] == "reject_once" }
          result = option ? { outcome: { outcome: "selected", optionId: option.fetch("optionId") } } : { outcome: { outcome: "cancelled" } }
          write_message(jsonrpc: "2.0", id: message["id"], result: result)
        else
          write_message(jsonrpc: "2.0", id: message["id"], error: {
            code: -32601,
            message: "Method not supported by the conformance probe"
          })
        end
      end

      def session_params
        { cwd: @cwd, mcpServers: mcp_servers }
      end

      def validate_content!(content)
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

      def require_session_capability!(name)
        raise ProtocolError, "session has not been created" unless @session_id
        raise Unsupported, "agent does not advertise session/#{name}" unless agent_capabilities.dig("sessionCapabilities", name)
      end

      def terminate_process
        return unless @wait_thread&.alive?

        signal_process("TERM")
        @wait_thread.join(1)
        return unless @wait_thread.alive?

        signal_process("KILL")
        @wait_thread.join(1)
      rescue Errno::ESRCH
        nil
      end

      def signal_process(signal)
        Process.kill(signal, -@pid)
      rescue Errno::EPERM
        Process.kill(signal, @pid)
      end
  end
end
