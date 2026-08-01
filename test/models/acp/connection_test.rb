require "test_helper"
require "rbconfig"
require "tmpdir"

class Acp::ConnectionTest < ActiveSupport::TestCase
  FAKE_AGENT = Rails.root.join("test/fixtures/files/acp/fake_agent.rb").to_s

  test "negotiates v1, correlates requests, denies permission, cancels, and keeps stderr separate" do
    with_connection(mode: "cancel") do |connection|
      initialized = connection.initialize_connection
      session = connection.new_session
      result = nil
      prompt_thread = Thread.new do
        result = connection.prompt([ { type: "text", text: "wait" } ])
      end

      event = connection.next_event(timeout: 2)
      connection.cancel
      prompt_thread.join(2)

      assert_equal 1, initialized["protocolVersion"]
      assert_equal "fake-session", session["sessionId"]
      assert_equal "session/update", event["method"]
      assert_equal "cancelled", result["stopReason"]
      refute prompt_thread.alive?
      assert_match(/stderr remains separate/, connection.stderr)
    end
  end

  test "normalizes mcp servers once and sends identical content on new resume and load" do
    source = [ { type: "http", name: "authorized", url: "http://127.0.0.1:3999/mcp", headers: [] } ]
    with_connection(mcp_servers: source) do |connection|
      connection.initialize_connection
      connection.new_session
      assert_equal source.as_json, connection.mcp_servers
      assert_equal({}, connection.resume("fake-session"))
      assert_equal({}, connection.load("fake-session"))
      assert_predicate connection.mcp_servers, :frozen?
    end
  end

  test "defaults mcp servers to empty until the supervisor configures authorization" do
    with_connection do |connection|
      connection.initialize_connection
      connection.new_session

      assert_equal [], connection.mcp_servers
    end
  end

  test "routes permission requests through the configured exact-session callback" do
    observed = nil
    with_connection do |connection|
      connection.configure_permission_handler! do |params|
        observed = params
        reject = params.fetch("options").find { |option| option["kind"] == "reject_once" }
        { outcome: { outcome: "selected", optionId: reject.fetch("optionId") } }
      end
      connection.initialize_connection
      connection.new_session

      result = connection.prompt([ { type: "text", text: "request permission" } ])

      assert_equal "fake-session", observed.fetch("sessionId")
      assert_equal "fake-tool", observed.dig("toolCall", "toolCallId")
      assert_equal "end_turn", result.fetch("stopReason")
    end
  end

  test "correlates out of order responses while both requests are live" do
    with_connection(mode: "out_of_order") do |connection|
      connection.initialize_connection
      connection.new_session
      results = {}
      threads = %w[first second].map do |cursor|
        Thread.new { results[cursor] = connection.list_sessions(cursor: cursor) }
      end
      threads.each { |thread| thread.join(2) }

      assert_equal "first", results.dig("first", "sessions", 0, "cursor")
      assert_equal "second", results.dig("second", "sessions", 0, "cursor")
      assert threads.none?(&:alive?)
    end
  end

  test "bounds malformed utf8 partial oversized unknown id hangs and early death" do
    {
      "malformed" => Acp::Connection::ProtocolError,
      "invalid_utf8" => Acp::Connection::ProtocolError,
      "partial" => Acp::Connection::ProtocolError,
      "oversized" => Acp::Connection::ProtocolError,
      "unknown_id" => Acp::Connection::ProtocolError,
      "hang" => Acp::Connection::TimeoutError,
      "early_exit" => Acp::Connection::ProcessError
    }.each do |mode, error_class|
      with_connection(mode: mode, timeout: 0.25, max_line_bytes: 1024) do |connection|
        assert_raises(error_class, "expected bounded #{mode} failure") { connection.initialize_connection }
      end
    end
  end

  test "duplicate response ids fail the connection" do
    with_connection(mode: "duplicate_id", queue_size: 1) do |connection|
      connection.initialize_connection
      wait_until { connection.failure }

      assert_kind_of Acp::Connection::ProtocolError, connection.failure
    end
  end

  test "retains a bounded tail without disconnecting during a streaming turn" do
    with_connection(mode: "streaming") do |connection|
      connection.initialize_connection
      connection.new_session

      result = connection.prompt([ { type: "text", text: "stream" } ])
      updates = connection.drain_events

      assert_equal "end_turn", result["stopReason"]
      assert_equal Acp::Connection::DEFAULT_QUEUE_SIZE, updates.length
      assert_equal 300 - Acp::Connection::DEFAULT_QUEUE_SIZE, connection.dropped_event_count
      assert_predicate connection, :running?
    end
  end

  test "drains a stderr flood without blocking protocol responses and keeps a bounded tail" do
    with_connection(mode: "stderr_flood") do |connection|
      connection.initialize_connection
      connection.new_session
      wait_until { connection.stderr.bytesize == Acp::Connection::STDERR_LIMIT }

      assert_equal Acp::Connection::STDERR_LIMIT, connection.stderr.bytesize
    end
  end

  test "rejects oversized outbound frames before they reach the child" do
    with_connection(max_line_bytes: 1024) do |connection|
      connection.initialize_connection
      connection.new_session

      assert_raises(Acp::Connection::ProtocolError) do
        connection.prompt([ { type: "text", text: "x" * 2_000 } ])
      end
    end
  end

  test "terminates the process group, drains descendants to eof, and permits a fresh connection" do
    Dir.mktmpdir("acp-descendant-test") do |workspace|
      pid_file = File.join(workspace, "descendant.pid")
      connection = build_connection(
        workspace: workspace,
        mode: "descendant",
        environment: { "FAKE_DESCENDANT_PID_FILE" => pid_file }
      ).start
      connection.initialize_connection
      wait_until { File.exist?(pid_file) }
      descendant_pid = Integer(File.read(pid_file))

      connection.stop

      assert_process_gone(descendant_pid)
      replacement = build_connection(workspace: workspace).start
      assert_equal 1, replacement.initialize_connection["protocolVersion"]
      replacement.stop
    ensure
      connection&.stop
      replacement&.stop
    end
  end

  test "stop is safe before the connection starts" do
    Dir.mktmpdir("acp-stop-before-start") do |workspace|
      connection = build_connection(workspace: workspace)

      assert_nil connection.stop
      assert_nil connection.stop
    end
  end

  private
    def with_connection(mode: "normal", timeout: 2, max_line_bytes: Acp::Connection::DEFAULT_MAX_LINE_BYTES,
      queue_size: Acp::Connection::DEFAULT_QUEUE_SIZE, mcp_servers: [], environment: {})
      Dir.mktmpdir("acp-connection-test") do |workspace|
        connection = build_connection(
          workspace: workspace,
          mode: mode,
          timeout: timeout,
          max_line_bytes: max_line_bytes,
          queue_size: queue_size,
          mcp_servers: mcp_servers,
          environment: environment
        ).start
        yield connection
      ensure
        connection&.stop
      end
    end

    def build_connection(workspace:, mode: "normal", timeout: 2,
      max_line_bytes: Acp::Connection::DEFAULT_MAX_LINE_BYTES,
      queue_size: Acp::Connection::DEFAULT_QUEUE_SIZE, mcp_servers: [], environment: {})
      Acp::Connection.new(
        argv: [ RbConfig.ruby, FAKE_AGENT ],
        cwd: workspace,
        environment: {
          "FAKE_ACP_MODE" => mode,
          "FAKE_SESSION_ID" => "fake-session"
        }.merge(environment),
        mcp_servers: mcp_servers,
        timeout: timeout,
        max_line_bytes: max_line_bytes,
        queue_size: queue_size,
        termination_grace: 0.25
      )
    end

    def wait_until(timeout: 3)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
      until yield
        flunk "condition did not become true" if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
        sleep 0.01
      end
    end

    def assert_process_gone(pid)
      wait_until do
        Process.kill(0, pid)
        false
      rescue Errno::ESRCH
        true
      end
    end
end
