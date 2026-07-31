require "test_helper"
require "rbconfig"
require "tmpdir"

class Acp::SupervisorTest < ActiveSupport::TestCase
  FAKE_AGENT = Rails.root.join("test/fixtures/files/acp/fake_agent.rb").to_s

  test "creates a local session and runtime grant before first session new" do
    with_supervisor do |supervisor|
      before = Agent::Session.count
      agent_session = supervisor.start_session(conversation: agent_conversations(:active))

      assert_equal before + 1, Agent::Session.count
      assert_equal "fake-session-1", agent_session.external_session_id
      assert_equal "connected", agent_session.status
      assert_equal "authorized", agent_session.mcp_authorization_status
      assert_equal "1.0.0", agent_session.installation.agent_version
      server = supervisor.connection_for(agent_session).mcp_servers.sole
      assert_equal "http", server["type"]
      assert_equal "http://127.0.0.1:3000/mcp", server["url"]
      assert_match(/\ABearer /, server.fetch("headers").sole.fetch("value"))
      assert_equal 1, agent_session.grants.active_at.count
    end
  end

  test "failed initialization retains the local session and revokes its runtime grant" do
    assert_raises(Acp::Connection::ProtocolError) do
      with_supervisor(mode: "missing_session_id") do |supervisor|
        supervisor.start_session(conversation: agent_conversations(:active))
      end
    end

    failed = Agent::Session.order(:id).last
    assert_equal "failed", failed.status
    assert_nil failed.external_session_id
    assert_predicate failed.grants.sole, :revoked_at?
    assert_equal "session.initialization_failed", Agent::AuditEvent.where(agent_session: failed).order(:id).last.event_type
  end

  test "uses advertised load when resume is unavailable and rotates MCP authorization" do
    prepare_persisted_session
    grant = agent_grants(:active)
    with_supervisor(mode: "load_only") do |supervisor|
      recovered = supervisor.recover_session(agent_sessions(:connected))

      assert_equal "connected", recovered.status, recovered.recovery_error
      assert_equal "authorized", recovered.mcp_authorization_status
      assert_predicate grant.reload, :revoked_at?
      assert_equal 1, recovered.grants.active_at.count
      assert_nothing_raised { recovered.require_mcp_authorized! }
      assert supervisor.session_list_observations.key?(recovered.id)
      assert_equal "load", supervisor.recovery_methods[recovered.id]
    end
  end


  test "uses the stdio proxy when HTTP MCP is not advertised" do
    with_supervisor(mode: "stdio") do |supervisor|
      agent_session = supervisor.start_session(conversation: agent_conversations(:active))
      server = supervisor.connection_for(agent_session).mcp_servers.sole

      assert_equal Rails.root.join("bin/hearth-mcp-proxy").to_s, server["command"]
      assert_equal [], server["args"]
      assert_equal %w[HEARTH_MCP_BEARER HEARTH_MCP_URL], server.fetch("env").pluck("name").sort
      refute_includes server["command"], server.fetch("env").find { |item| item["name"] == "HEARTH_MCP_BEARER" }.fetch("value")
    end
  end

  test "falls back from a rejected resume to advertised load" do
    prepare_persisted_session
    with_supervisor(mode: "reject_resume") do |supervisor|
      recovered = supervisor.recover_session(agent_sessions(:connected))

      assert_equal "connected", recovered.status, recovered.recovery_error
      assert_nil recovered.recovery_error
      assert_equal "load", supervisor.recovery_methods[recovered.id]
    end
  end

  test "records one truthful terminal failure when neither resume nor load is advertised" do
    prepare_persisted_session
    with_supervisor(mode: "no_recovery") do |supervisor|
      failed = supervisor.recover_session(agent_sessions(:connected))

      assert_equal "failed", failed.status
      assert_match(/neither session\/resume nor session\/load/, failed.recovery_error)
      events = Agent::AuditEvent.where(
        agent_session: failed,
        event_type: "session.recovery_failed"
      )
      assert_equal 1, events.count
      assert_equal failed.recovery_error, events.sole.metadata["reason"]
    end
  end

  test "exhausts bounded retry backoff through an injected fatal callback" do
    prepare_persisted_session
    calls = []
    with_supervisor(
      mode: "hang",
      timeout: 0.1,
      recovery_backoffs: [ 0, 0, 0 ],
      on_fatal: ->(agent_session, error) { calls << [ agent_session.id, error.class ] }
    ) do |supervisor|
      4.times { supervisor.recover_session(agent_sessions(:connected).reload) }

      failed = agent_sessions(:connected).reload
      assert_equal "failed", failed.status
      assert_equal [ [ failed.id, Acp::Connection::TimeoutError ] ], calls
      assert_equal 1, Agent::AuditEvent.where(
        agent_session: failed,
        event_type: "session.recovery_failed"
      ).count
    end
  end

  test "a hung connection cannot block a second concurrent session" do
    modes = [ "hang_prompt", "normal" ]
    with_supervisor(connection_factory: connection_factory(modes: modes)) do |supervisor|
      first = supervisor.start_session(conversation: agent_conversations(:active))
      second_conversation = Agent::Conversation.create!(
        household: households(:home),
        person: people(:two),
        profile: agent_profiles(:hearth),
        title: "Concurrent isolation"
      )
      second = supervisor.start_session(conversation: second_conversation)
      first_error = nil
      first_thread = Thread.new do
        Thread.current.report_on_exception = false
        supervisor.prompt(first, [ { type: "text", text: "hang" } ])
      rescue => error
        first_error = error
      end

      healthy = supervisor.prompt(second, [ { type: "text", text: "healthy" } ])
      supervisor.connection_for(first).stop
      first_thread.join(2)

      assert_equal "end_turn", healthy["stopReason"]
      assert_kind_of Acp::Connection::Error, first_error
      refute first_thread.alive?
      assert_predicate supervisor.connection_for(second), :running?
    end
  end

  test "an unmodelled recovery error fails only that session" do
    healthy_factory = connection_factory(modes: [ "normal" ])
    calls = 0
    factory = lambda do |**arguments|
      calls += 1
      raise "unexpected adapter failure" if calls == 2

      healthy_factory.call(**arguments)
    end

    with_supervisor(connection_factory: factory) do |supervisor|
      healthy = supervisor.start_session(conversation: agent_conversations(:active))

      failed = supervisor.recover_session(agent_sessions(:connected))

      assert_equal "failed", failed.status
      assert_match(/unexpected adapter failure/, failed.recovery_error)
      assert_predicate supervisor.connection_for(healthy), :running?
    end
  end

  test "disabled profiles cannot start or recover and disconnect an attached session" do
    with_supervisor do |supervisor|
      agent_session = supervisor.start_session(conversation: agent_conversations(:active))
      agent_session.conversation.profile.update!(enabled: false)

      supervisor.tick
      supervisor.tick

      assert_equal "disconnected", agent_session.reload.status
      assert_equal "Agent profile is disabled", agent_session.recovery_error
      assert_raises(Acp::Supervisor::Error) { supervisor.connection_for(agent_session) }
      assert_raises(Acp::Supervisor::ProfileDisabled) do
        supervisor.start_session(conversation: agent_conversations(:active))
      end
    end
  end

  test "shutdown removes an exact descendant and the supervisor can be reused" do
    Dir.mktmpdir("acp-supervisor-descendant") do |pid_workspace|
      pid_file = File.join(pid_workspace, "descendant.pid")
      factory = connection_factory(
        modes: [ "descendant", "normal" ],
        extra_environment: { "FAKE_DESCENDANT_PID_FILE" => pid_file }
      )
      with_instance_root do |root|
        configure_profile
        first = Acp::Supervisor.new(instance_root: root, connection_factory: factory).start!
        agent_session = first.start_session(conversation: agent_conversations(:active))
        wait_until { File.exist?(pid_file) }
        descendant_pid = Integer(File.read(pid_file))
        first.shutdown!

        assert_process_gone(descendant_pid)
        replacement = Acp::Supervisor.new(instance_root: root, connection_factory: factory).start!
        recovered = replacement.recover_session(agent_session.reload)
        assert_equal "connected", recovered.status, recovered.recovery_error
        replacement.shutdown!
      ensure
        first&.shutdown!
        replacement&.shutdown!
      end
    end
  end

  private
    def with_supervisor(mode: "normal", timeout: 2, recovery_backoffs: [ 0, 0, 0 ],
      on_fatal: ->(_session, _error) { }, connection_factory: nil)
      with_instance_root do |root|
        configure_profile
        supervisor = Acp::Supervisor.new(
          instance_root: root,
          connection_factory: connection_factory || self.connection_factory(modes: [ mode ], timeout: timeout),
          recovery_backoffs: recovery_backoffs,
          on_fatal: on_fatal
        ).start!
        yield supervisor
      ensure
        supervisor&.shutdown!
      end
    end

    def connection_factory(modes:, timeout: 2, extra_environment: {})
      count = 0
      lambda do |**arguments|
        mode = modes.fetch([ count, modes.length - 1 ].min)
        count += 1
        arguments = arguments.merge(
          environment: arguments.fetch(:environment).merge(
            "FAKE_ACP_MODE" => mode,
            "FAKE_SESSION_ID" => "fake-session-#{count}"
          ).merge(extra_environment),
          timeout: timeout,
          termination_grace: 0.2
        )
        Acp::Connection.new(**arguments)
      end
    end

    def configure_profile
      agent_profiles(:hearth).update!(
        executable_path: RbConfig.ruby,
        arguments: [ FAKE_AGENT ],
        environment_keys: []
      )
    end

    def prepare_persisted_session
      configure_profile
      agent_installations(:local).update!(
        external_id: "fake-agent",
        executable_path: RbConfig.ruby,
        agent_version: "1.0.0"
      )
      agent_sessions(:connected).update!(external_session_id: "fake-session-1")
    end

    def with_instance_root
      Dir.mktmpdir("hearth-supervisor") do |root|
        FileUtils.mkdir_p(File.join(root, ".hearth"))
        File.write(File.join(root, ".hearth/instance.yml"), "---\n")
        yield root
      end
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
