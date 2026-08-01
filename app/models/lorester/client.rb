require "json"
require "open3"
require "socket"

class Lorester::Client
  CONTRACT_VERSION = 1
  MAX_FRAME_BYTES = 1_048_576
  MAX_ROOT_OUTPUT_BYTES = 65_536
  DEFAULT_TIMEOUT = 5.0

  class Error < StandardError
    attr_reader :code

    def initialize(code, message)
      @code = code
      super(message)
    end
  end

  def initialize(vault: ENV["LORESTER_VAULT"], executable: ENV.fetch("LORESTER_EXECUTABLE", "lorester"),
    data_dir: ENV["LORESTER_DATA_DIR"], timeout: DEFAULT_TIMEOUT, socket_factory: UNIXSocket.method(:new))
    @vault = vault
    @executable = executable
    @data_dir = data_dir
    @timeout = timeout
    @socket_factory = socket_factory
  end

  def discover = request("knowledge_discover", contract_version: CONTRACT_VERSION, expected_type: "discovery")
  def search(query) = request("knowledge_search", contract_version: CONTRACT_VERSION, query: query, expected_type: "search")
  def read(note_id) = request("knowledge_read", contract_version: CONTRACT_VERSION, note_id: note_id, expected_type: "note")
  def related(note_id) = request("knowledge_related", contract_version: CONTRACT_VERSION, note_id: note_id, expected_type: "related")

  def submit(request_id:, origin:, content:, conversation_reference:, message_reference:, requested_intent:)
    request(
      "knowledge_submit",
      contract_version: CONTRACT_VERSION,
      request_id: request_id,
      origin: origin,
      household_safe_redacted: true,
      content: content,
      conversation_reference: conversation_reference,
      message_reference: message_reference,
      requested_intent: requested_intent,
      expected_type: "submitted"
    )
  end

  def submission_status(submission_id)
    request(
      "knowledge_submission_status",
      contract_version: CONTRACT_VERSION,
      submission_id: submission_id,
      expected_type: "submission_status"
    )
  end

  private
    attr_reader :vault, :executable, :data_dir, :timeout, :socket_factory

    def request(operation, expected_type:, **payload)
      root = discover_root
      socket = socket_factory.call(root.fetch("endpoint"))
      deadline = monotonic_now + timeout
      write_frame(socket, { operation: "hello", vault_id: root.fetch("vault_id") }, deadline)
      hello = read_frame(socket, deadline)
      hello_result = hello["result"]
      unless hello["ok"] == true && hello.keys.sort == %w[ok result] &&
          hello_result.is_a?(Hash) && hello_result.keys.sort == %w[protocol_version type vault_id] &&
          hello_result["type"] == "hello_ack" && hello_result["vault_id"] == root.fetch("vault_id") &&
          hello_result["protocol_version"].is_a?(Integer) && hello_result["protocol_version"].positive?
        raise Error.new("stopped", "Lorester owner handshake failed")
      end

      write_frame(socket, { operation: operation }.merge(payload), deadline)
      decode_response(read_frame(socket, deadline), expected_type: expected_type)
    rescue Errno::ENOENT, Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::EPIPE, EOFError, IOError, SystemCallError => error
      raise Error.new("stopped", "Lorester owner is unavailable (#{error.class.name})")
    ensure
      socket&.close
    end

    def discover_root
      raise Error.new("not_configured", "Lorester vault is not configured") if vault.blank?

      environment = data_dir.present? ? { "LORESTER_DATA_DIR" => data_dir } : {}
      stdout, stderr, status = capture_process(environment, executable, "--json", "root", "--vault", vault)
      raise Error.new("unavailable", "Lorester root discovery failed") unless status.success?

      envelope = JSON.parse(stdout)
      result = envelope.fetch("result")
      unless envelope["ok"] == true && result.is_a?(Hash) &&
          result["vault_id"].is_a?(String) && result["vault_id"].present? &&
          result["endpoint"].is_a?(String) && result["endpoint"].present?
        raise Error.new("incompatible", "Lorester root discovery returned an incompatible response")
      end
      result.slice("vault_id", "endpoint")
    rescue JSON::ParserError, KeyError, TypeError
      raise Error.new("incompatible", "Lorester root discovery returned an incompatible response")
    rescue Errno::ENOENT
      raise Error.new("unavailable", "Lorester executable is unavailable")
    end

    def capture_process(environment, *command)
      stdout = +""
      stderr = +""
      Open3.popen3(environment, *command) do |stdin, out, err, wait_thread|
        stdin.close
        readers = [ [ out, stdout ], [ err, stderr ] ].map do |stream, buffer|
          Thread.new do
            while (chunk = stream.readpartial(16_384))
              remaining = MAX_ROOT_OUTPUT_BYTES - buffer.bytesize
              buffer << chunk.byteslice(0, remaining) if remaining.positive?
            end
          rescue EOFError
          end
        end
        unless wait_thread.join(timeout)
          Process.kill("TERM", wait_thread.pid)
          wait_thread.join(0.5) || Process.kill("KILL", wait_thread.pid)
          wait_thread.join
          raise Error.new("unavailable", "Lorester root discovery timed out")
        end
        readers.each(&:join)
        return [ stdout, stderr, wait_thread.value ]
      end
    end

    def write_frame(socket, payload, deadline)
      json = JSON.generate(payload)
      raise Error.new("incompatible", "Lorester request exceeds the frame limit") if json.bytesize > MAX_FRAME_BYTES

      write_all(socket, [ json.bytesize ].pack("N") + json, deadline)
    end

    def read_frame(socket, deadline)
      length = read_exact(socket, 4, deadline).unpack1("N")
      raise Error.new("incompatible", "Lorester response exceeds the frame limit") if length > MAX_FRAME_BYTES

      JSON.parse(read_exact(socket, length, deadline))
    rescue JSON::ParserError
      raise Error.new("incompatible", "Lorester returned invalid JSON")
    end

    def write_all(socket, bytes, deadline)
      offset = 0
      while offset < bytes.bytesize
        wait_for(socket, :write, deadline)
        written = socket.write_nonblock(bytes.byteslice(offset..), exception: false)
        next if written == :wait_writable
        raise EOFError, "closed stream" if written.nil? || written.zero?
        offset += written
      end
    end

    def read_exact(socket, length, deadline)
      result = +""
      while result.bytesize < length
        wait_for(socket, :read, deadline)
        chunk = socket.read_nonblock(length - result.bytesize, exception: false)
        next if chunk == :wait_readable
        raise EOFError, "closed stream" if chunk.nil?
        result << chunk
      end
      result
    end

    def wait_for(socket, direction, deadline)
      remaining = deadline - monotonic_now
      raise Error.new("unavailable", "Lorester request timed out") unless remaining.positive?

      ready = direction == :read ? IO.select([ socket ], nil, nil, remaining) : IO.select(nil, [ socket ], nil, remaining)
      raise Error.new("unavailable", "Lorester request timed out") unless ready
    end

    def decode_response(envelope, expected_type:)
      unless envelope.is_a?(Hash) && (envelope.keys - %w[ok result error]).empty?
        raise Error.new("incompatible", "Lorester returned an incompatible response envelope")
      end
      unless envelope["ok"]
        failure = envelope["error"]
        raise Error.new(error_code(failure&.fetch("code", nil)), "Lorester knowledge request failed")
      end

      result = envelope.fetch("result")
      response = result.fetch("response")
      unless result.keys.sort == %w[response type] && result["type"] == "knowledge" &&
          response.is_a?(Hash) && response["type"] == expected_type
        raise Error.new("incompatible", "Lorester returned an incompatible knowledge response")
      end
      validate_response!(response, expected_type)
      response.except("type")
    rescue KeyError, TypeError
      raise Error.new("incompatible", "Lorester returned an incompatible knowledge response")
    end

    def validate_response!(response, type)
      case type
      when "discovery"
        exact_keys!(response, %w[contract_version control_protocol_version owner_started_at readiness source_commit type])
        raise TypeError unless response["contract_version"] == CONTRACT_VERSION
        raise TypeError unless response["readiness"].in?(%w[ready unavailable stale incompatible])
      when "search", "related"
        exact_keys!(response, %w[notes truncated type])
        raise TypeError unless response["notes"].is_a?(Array) && response["notes"].length <= 20
        response["notes"].each { |note| validate_note!(note) }
      when "note"
        validate_note!(response)
      when "submitted", "submission_status"
        allowed = %w[diagnostic state submission_id type updated_at]
        raise TypeError unless (response.keys - allowed).empty? && %w[state submission_id type updated_at].all? { |key| response.key?(key) }
        raise TypeError unless response["state"].in?(%w[accepted materialized admitted processing complete failed unavailable])
      else
        raise TypeError
      end
    rescue TypeError
      raise Error.new("incompatible", "Lorester returned an incompatible #{type} response")
    end

    def validate_note!(note)
      required = %w[id title description excerpt citation]
      allowed = required + %w[type]
      raise TypeError unless note.is_a?(Hash) && (note.keys - allowed).empty? && required.all? { |key| note.key?(key) }
      raise TypeError if note.key?("type") && note["type"] != "note"
      citation = note.fetch("citation")
      raise TypeError unless citation.keys.sort == %w[contract_version source_commit] && citation["contract_version"] == CONTRACT_VERSION
      [ note.fetch("title"), note.fetch("excerpt"), note["description"] ].compact.each do |bounded|
        raise TypeError unless bounded.keys.sort == %w[text truncated]
      end
    end

    def exact_keys!(value, keys)
      raise TypeError unless value.is_a?(Hash) && value.keys.sort == keys.sort
    end

    def error_code(value)
      normalized = value.to_s.underscore
      return "pressure" if normalized.include?("pressure")
      return "in_progress" if normalized.include?("request_in_progress")
      return "idempotency_conflict" if normalized.include?("idempotency_conflict")
      return "stale" if normalized.include?("stale")
      return "not_found" if normalized.include?("not_found")
      return "incompatible" if normalized.include?("incompatible")
      return "unavailable" if normalized.include?("unavailable")
      return "authorization" if normalized.include?("authorization")
      return "validation" if normalized.include?("validation")

      "unavailable"
    end

    def monotonic_now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
end
