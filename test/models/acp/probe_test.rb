require "test_helper"
require "rbconfig"
require "tmpdir"

class Acp::ProbeTest < ActiveSupport::TestCase
  FAKE_AGENT = Rails.root.join("test/fixtures/files/acp/fake_agent.rb").to_s
  ATTACHMENT = Rails.root.join("test/fixtures/files/acp/attachment.txt").to_s
  IMAGE = Rails.root.join("test/fixtures/files/acp/attachment.png").to_s

  test "negotiates ACP, denies permissions, preserves streamed update order, and exercises lifecycle methods" do
    with_probe do |probe|
      initialized = probe.initialize_connection
      session = probe.new_session
      result = probe.prompt([ { type: "text", text: "probe" } ])

      assert_equal 1, initialized["protocolVersion"]
      assert_equal "fake-session", session["sessionId"]
      assert_equal "end_turn", result["stopReason"]
      assert_equal %w[HEARTH_ ACP_OK], probe.updates.map { |entry| entry.dig("update", "content", "text") }
      assert_equal({}, probe.resume)
      assert_equal({}, probe.load)
      assert_equal({}, probe.close)
      assert_match(/stderr remains separate/, probe.stderr)
    end
  end

  test "uses the same negotiated HTTP MCP server for new resume and load" do
    with_probe do |probe|
      probe.initialize_connection
      probe.new_session

      assert_equal [ {
        type: "http",
        name: "hearth-spike",
        url: "http://127.0.0.1:3999/mcp",
        headers: []
      } ], probe.mcp_servers
      assert_equal({}, probe.resume)
      assert_equal({}, probe.load)
    end
  end

  test "uses the absolute stdio proxy when HTTP MCP is not advertised" do
    with_probe(mode: "stdio") do |probe|
      probe.initialize_connection
      probe.new_session

      server = probe.mcp_servers.first
      assert_equal Rails.root.join("bin/hearth-mcp-spike-proxy").to_s, server[:command]
      assert Pathname.new(server[:command]).absolute?
      assert_equal [ { name: "HEARTH_MCP_URL", value: "http://127.0.0.1:3999/mcp" } ], server[:env]
      assert_equal({}, probe.resume)
      assert_equal({}, probe.load)
    end
  end

  test "sends actual embedded resource and image content when advertised" do
    with_probe do |probe|
      probe.initialize_connection
      probe.new_session

      result = probe.prompt([
        { type: "text", text: "inspect attachments" },
        probe.text_resource(ATTACHMENT),
        probe.image(IMAGE)
      ])

      assert_equal "end_turn", result["stopReason"]
    end
  end

  test "rejects unadvertised attachments before writing a prompt" do
    with_probe(mode: "no_attachments") do |probe|
      probe.initialize_connection
      probe.new_session

      assert_raises(Acp::Probe::Unsupported) { probe.prompt([ probe.text_resource(ATTACHMENT) ]) }
      assert_raises(Acp::Probe::Unsupported) { probe.prompt([ probe.image(IMAGE) ]) }
      assert_equal({}, probe.close)
    end
  end

  test "authenticates only with an advertised method" do
    with_probe(mode: "auth") do |probe|
      probe.initialize_connection
      assert_equal({}, probe.authenticate("fake-auth"))
      assert_raises(Acp::Probe::Unsupported) { probe.authenticate("missing") }
    end
  end

  test "cancels an in-flight prompt without deadlock" do
    with_probe(mode: "cancel") do |probe|
      probe.initialize_connection
      probe.new_session
      result = nil
      prompt_thread = Thread.new { result = probe.prompt([ { type: "text", text: "wait" } ]) }

      Timeout.timeout(2) { sleep 0.01 until probe.updates.any? }
      probe.cancel
      prompt_thread.join(2)

      assert_equal "cancelled", result["stopReason"]
      refute prompt_thread.alive?
    end
  end

  test "bounds malformed oversized unknown-id timeout and early-exit failures" do
    {
      "malformed" => Acp::Probe::ProtocolError,
      "oversized" => Acp::Probe::ProtocolError,
      "unknown_id" => Acp::Probe::ProtocolError,
      "hang" => Acp::Probe::Error,
      "early_exit" => Acp::Probe::Error
    }.each do |mode, error|
      with_probe(mode: mode, timeout: 1, max_line_bytes: 1024) do |probe|
        assert_raises(error, "expected bounded #{mode} failure") { probe.initialize_connection }
      end
    end
  end

  test "owns the agent process directly and leaves no process after cleanup" do
    pid = nil
    with_probe do |probe|
      pid = probe.pid
      probe.initialize_connection
      assert_equal Process.pid, probe.agent_info["ppid"]
      assert_equal Process.pid, Integer(`ps -o ppid= -p #{pid}`)
    end

    assert_raises(Errno::ESRCH) { Process.kill(0, pid) }
  end

  private
    def with_probe(mode: "normal", timeout: 2, max_line_bytes: Acp::Probe::DEFAULT_MAX_LINE_BYTES)
      Dir.mktmpdir("acp-probe-test") do |workspace|
        argv = [ "/usr/bin/env", "FAKE_ACP_MODE=#{mode}", RbConfig.ruby, FAKE_AGENT ]
        probe = Acp::Probe.new(
          argv: argv,
          cwd: workspace,
          mcp_url: "http://127.0.0.1:3999/mcp",
          timeout: timeout,
          max_line_bytes: max_line_bytes
        ).start
        yield probe
      ensure
        probe&.stop
      end
    end
end
