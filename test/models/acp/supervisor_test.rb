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

  test "acceptance supervisor issues the fixed read-only grant without changing the default" do
    environments = []
    factory = connection_factory(modes: [ "no_auth" ])
    capturing_factory = lambda do |**arguments|
      environments << arguments.fetch(:environment)
      factory.call(**arguments)
    end
    with_supervisor(
      runtime_capability_groups: Agent::Grant::READ_ONLY_RUNTIME_GROUPS,
      acceptance_environment: Agent::Profile::Certified::GROK_ACCEPTANCE_ENVIRONMENT,
      connection_factory: capturing_factory
    ) do |supervisor|
      agent_session = supervisor.start_session(conversation: agent_conversations(:active))

      assert_equal %w[health_read knowledge_read], agent_session.grants.active_at.sole.capability_groups
      assert_equal "0", environments.sole.fetch("GROK_CLAUDE_AGENTS_ENABLED")
      refute_includes agent_session.conversation.profile.environment_keys, "GROK_CLAUDE_AGENTS_ENABLED"
    end
  end

  test "advertised default and sole methods send no authenticate frame without operator approval" do
    %w[default_auth sole_auth].each do |mode|
      Dir.mktmpdir("hearth-auth-wire") do |directory|
        auth_log = File.join(directory, "authenticate.log")
        factory = connection_factory(modes: [ mode ], extra_environment: { "FAKE_AUTH_LOG" => auth_log })

        error = assert_raises(Acp::Supervisor::AuthenticationRequired) do
          with_supervisor(connection_factory: factory) do |supervisor|
            supervisor.start_session(conversation: agent_conversations(:active))
          end
        end
        assert_match(/Agent settings/i, error.message)
        refute_match(/bin\/hearth|terminal|command line/i, error.message)
        refute File.exist?(auth_log), "#{mode} inferred authentication without approval"
        installation = agent_profiles(:hearth).installations.find_by!(
          external_id: "profile-#{agent_profiles(:hearth).id}"
        )
        assert_equal "required", installation.authentication_status
        assert_nil installation.authentication_method_id
      end
    end
  end

  test "failed provider authentication directs the user to Agent settings without CLI guidance" do
    installation = agent_installations(:local)
    installation.update!(
      authentication_methods: [ { "id" => "fake-auth", "name" => "Fake authentication" } ],
      authentication_status: "required",
      authentication_method_id: nil,
      authentication_approved_at: nil,
      authentication_origin: nil
    )
    installation.approve_authentication!(method_id: "fake-auth")

    error = assert_raises(Acp::Supervisor::AuthenticationRequired) do
      with_supervisor(mode: "auth_failure") do |supervisor|
        supervisor.start_session(conversation: agent_conversations(:active))
      end
    end

    assert_match(/Agent settings/i, error.message)
    refute_match(/bin\/hearth|terminal|command line/i, error.message)
  end

  test "recovery also sends no authenticate frame without operator approval" do
    %w[default_auth sole_auth].each do |mode|
      prepare_persisted_session
      installation = agent_installations(:local)
      installation.update_columns(
        authentication_method_id: nil,
        authentication_approved_at: nil,
        authentication_origin: nil,
        authentication_status: "required"
      )
      agent_sessions(:connected).update_columns(status: "connected", recovery_error: nil)
      Dir.mktmpdir("hearth-recovery-auth-wire") do |directory|
        auth_log = File.join(directory, "authenticate.log")
        factory = connection_factory(modes: [ mode ], extra_environment: { "FAKE_AUTH_LOG" => auth_log })
        with_supervisor(connection_factory: factory) do |supervisor|
          recovered = supervisor.recover_session(agent_sessions(:connected))
          assert_equal "failed", recovered.status
          assert_match(/Agent settings/i, recovered.recovery_error)
          refute_match(/bin\/hearth|terminal|command line/i, recovered.recovery_error)
        end
        refute File.exist?(auth_log), "#{mode} inferred authentication during recovery"
      end
    end
  end

  test "an operator approved method is authenticated and reused" do
    prepare_persisted_session
    installation = agent_installations(:local)
    installation.update!(
      authentication_methods: [ { "id" => "fake-auth", "name" => "Fake authentication" } ],
      authentication_status: "required",
      authentication_method_id: nil,
      authentication_approved_at: nil,
      authentication_origin: nil
    )
    installation.approve_authentication!(method_id: "fake-auth")

    Dir.mktmpdir("hearth-approved-auth") do |directory|
      auth_log = File.join(directory, "authenticate.log")
      factory = connection_factory(
        modes: [ "sole_auth" ],
        extra_environment: { "FAKE_AUTH_LOG" => auth_log, "FAKE_SESSION_ID" => "approved-session" }
      )
      with_supervisor(connection_factory: factory) do |supervisor|
        session = supervisor.start_session(conversation: agent_conversations(:active))
        assert_equal "connected", session.status
        assert_equal "authenticated", session.authentication_status
      end
      assert_equal [ "authenticate\n" ], File.readlines(auth_log)
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

  test "proposal-first permission waits off the reader thread and returns one approval" do
    Current.session = sessions(:browser)
    Current.household = households(:home)
    Current.person = people(:two)
    meal = meals(:sam_recipe_target_week)
    arguments = { "id" => meal.id }
    idempotency_key = "supervisor-delete-meal"
    factory = connection_factory(
      modes: [ "permission_allow" ],
      extra_environment: {
        "FAKE_PERMISSION_OPERATION" => "delete_meal",
        "FAKE_PERMISSION_INPUT" => JSON.generate(arguments.merge("idempotency_key" => idempotency_key))
      }
    )

    with_supervisor(connection_factory: factory) do |supervisor|
      agent_session = supervisor.start_session(
        conversation: agent_conversations(:active), browser_session: Current.session
      )
      Agent::OperationalAuthorization.authorize!(agent_session: agent_session, reason: "Permission bridge test")
      agent_session.update!(status: "starting")
      grant = agent_session.issue_runtime_grant!.grant
      expected = Agent::Mutation::Operations.expected_state(
        operation: "delete_meal", arguments: arguments, proposal: grant
      )
      proposal, token = Agent::MutationProposal.propose!(
        grant: grant, capability: "health.write", operation: "delete_meal", arguments: arguments,
        preview: Agent::Mutation::Operations.preview(operation: "delete_meal", arguments: arguments, context: grant),
        expected_state: expected, idempotency_key: idempotency_key, deadline_at: 5.seconds.from_now
      )

      prompt_result = nil
      prompt_thread = Thread.new do
        prompt_result = supervisor.prompt(agent_session, [ { type: "text", text: "request staged permission" } ])
      end
      wait_until { proposal.permission_request.reload.external_request_id == "fake-tool" }

      listed = supervisor.connection_for(agent_session).list_sessions
      assert_equal "fake-session-1", listed.fetch("sessions").sole.fetch("sessionId")
      proposal.decide!(outcome: "approved", by: users(:two), token: token)
      prompt_thread.join(3)

      assert_equal "end_turn", prompt_result.fetch("stopReason")
      assert_equal "executed", proposal.reload.status
      assert_not Meal.exists?(meal.id)
      assert_equal 1, Agent::MutationExecution.where(mutation_proposal: proposal).count
    end
  ensure
    Current.reset
  end

  test "permission-first and mismatched requests are rejected with stable structured reasons" do
    supervisor = Acp::Supervisor.new(instance_root: Dir.pwd)
    agent_session = agent_sessions(:connected)
    agent_session.update!(external_session_id: "permission-contract-session")
    base = {
      "sessionId" => agent_session.external_session_id,
      "toolCall" => { "toolCallId" => "permission-first" },
      "options" => [
        { "optionId" => "allow", "kind" => "allow_once" },
        { "optionId" => "reject", "kind" => "reject_once" }
      ]
    }

    missing_input = supervisor.send(:resolve_permission, agent_session, base)
    missing_key = supervisor.send(:resolve_permission, agent_session, base.deep_merge(
      "toolCall" => { "title" => "delete_meal", "rawInput" => {} }
    ))
    unstaged = supervisor.send(:resolve_permission, agent_session, base.deep_merge(
      "toolCall" => { "title" => "delete_meal", "rawInput" => { "idempotency_key" => "unstaged-key" } }
    ))

    [ missing_input, missing_key, unstaged ].each do |result|
      assert_equal "reject", result.dig(:outcome, :optionId)
      assert_equal "stage_required", result.dig(:_meta, :hearth, :code)
      assert_match(/stage|Call the typed/i, result.dig(:_meta, :hearth, :message))
    end
    assert_empty Agent::MutationProposal.where(agent_session: agent_session)
  end

  test "permission request rejects a staged proposal with mismatched operation or input" do
    Current.session = sessions(:browser)
    Current.household = households(:home)
    Current.person = people(:two)
    agent_session = agent_sessions(:connected)
    agent_session.update!(external_session_id: "permission-mismatch-session")
    Agent::OperationalAuthorization.authorize!(agent_session: agent_session, reason: "Correlation test")
    agent_session.update!(status: "starting")
    grant = agent_session.issue_runtime_grant!.grant
    meal = meals(:sam_recipe_target_week)
    arguments = { "id" => meal.id }
    proposal, = Agent::MutationProposal.propose!(
      grant: grant, capability: "health.write", operation: "delete_meal", arguments: arguments, preview: {},
      expected_state: Agent::Mutation::Operations.expected_state(operation: "delete_meal", arguments: arguments, proposal: grant),
      idempotency_key: "permission-mismatch", deadline_at: 1.minute.from_now
    )
    base = {
      "sessionId" => agent_session.external_session_id,
      "toolCall" => { "toolCallId" => "mismatch", "title" => "update_meal" },
      "options" => [ { "optionId" => "reject", "kind" => "reject_once" } ]
    }
    supervisor = Acp::Supervisor.new(instance_root: Dir.pwd)

    wrong_operation = supervisor.send(:resolve_permission, agent_session, base.deep_merge(
      "toolCall" => { "rawInput" => arguments.merge("idempotency_key" => proposal.idempotency_key) }
    ))
    wrong_input = supervisor.send(:resolve_permission, agent_session, base.deep_merge(
      "toolCall" => {
        "title" => "delete_meal",
        "rawInput" => { "id" => meal.id + 1, "idempotency_key" => proposal.idempotency_key }
      }
    ))

    [ wrong_operation, wrong_input ].each do |result|
      assert_equal "reject", result.dig(:outcome, :optionId)
      assert_equal "correlation_mismatch", result.dig(:_meta, :hearth, :code)
    end
    assert_equal "pending", proposal.reload.status
    assert Meal.exists?(meal.id)
  ensure
    Current.reset
  end

  test "proposal-first permission maps denial and timeout to reject once" do
    Current.session = sessions(:browser)
    Current.household = households(:home)
    Current.person = people(:two)
    agent_session = agent_sessions(:connected)
    agent_session.update!(external_session_id: "permission-terminal-session")
    Agent::OperationalAuthorization.authorize!(agent_session: agent_session, reason: "Permission terminal test")
    agent_session.update!(status: "starting")
    grant = agent_session.issue_runtime_grant!.grant
    supervisor = Acp::Supervisor.new(instance_root: Dir.pwd)
    meal = meals(:sam_recipe_target_week)

    denied, denied_token = stage_delete_proposal(grant, meal, "permission-denied", 1.minute.from_now)
    denied_result = nil
    denied_thread = Thread.new do
      denied_result = supervisor.send(:resolve_permission, agent_session, permission_params(agent_session, meal, denied.idempotency_key, "denied-tool"))
    end
    wait_until { denied.permission_request.reload.external_request_id == "denied-tool" }
    denied.decide!(outcome: "denied", by: users(:two), token: denied_token)
    denied_thread.join(2)

    assert_equal "reject", denied_result.dig(:outcome, :optionId)
    assert_equal "proposal_denied", denied_result.dig(:_meta, :hearth, :code)

    timed_out, = stage_delete_proposal(grant, meal, "permission-timeout", 0.2.seconds.from_now)
    timeout_result = supervisor.send(
      :resolve_permission, agent_session,
      permission_params(agent_session, meal, timed_out.idempotency_key, "timeout-tool")
    )

    assert_equal "reject", timeout_result.dig(:outcome, :optionId)
    assert_equal "proposal_expired", timeout_result.dig(:_meta, :hearth, :code)
    assert_equal "expired", timed_out.reload.status
    assert Meal.exists?(meal.id)
  ensure
    Current.reset
  end

  test "permission wait observes a committed decision when the pubsub notification is dropped" do
    Current.session = sessions(:browser)
    Current.household = households(:home)
    Current.person = people(:two)
    agent_session = agent_sessions(:connected)
    agent_session.update!(status: "starting")
    grant = agent_session.issue_runtime_grant!.grant
    meal = meals(:sam_recipe_target_week)
    proposal, = stage_delete_proposal(grant, meal, "dropped-permission-notification", 2.seconds.from_now)
    supervisor = Acp::Supervisor.new(instance_root: Dir.pwd)
    pubsub = ActionCable.server.pubsub
    with_stubbed_method(pubsub, :subscribe, ->(_channel, _callback, success) { success.call }) do
      waiter = Thread.new { supervisor.send(:wait_for_permission_decision, proposal, 2.seconds.from_now) }
      sleep 0.05
      proposal.update_column(:status, "denied")
      assert waiter.join(1), "database reconciliation did not wake promptly"
    end

    assert_equal "denied", proposal.reload.status
  ensure
    Current.reset
  end

  test "supervisor expires pending proposals and operational authorizations" do
    Current.session = sessions(:browser)
    Current.household = households(:home)
    Current.person = people(:two)
    agent_session = agent_sessions(:connected)
    authorization = Agent::OperationalAuthorization.authorize!(agent_session: agent_session, reason: "Expiry sweep")
    agent_session.update!(status: "starting")
    grant = agent_session.issue_runtime_grant!.grant
    meal = meals(:sam_recipe_target_week)
    arguments = { id: meal.id }
    proposal, = Agent::MutationProposal.propose!(
      grant: grant, capability: "health.write", operation: "delete_meal", arguments: arguments, preview: {},
      expected_state: Agent::Mutation::Operations.expected_state(operation: "delete_meal", arguments: arguments, proposal: grant),
      idempotency_key: "sweep-expired-proposal", deadline_at: 1.minute.from_now
    )
    proposal.update_column(:deadline_at, 1.second.ago)
    supervisor = Acp::Supervisor.new(instance_root: Dir.pwd)

    supervisor.send(:expire_pending_mutations)

    assert_equal "expired", proposal.reload.status
    assert_equal "expired", proposal.permission_request.reload.status

    authorization.update_column(:expires_at, 1.second.ago)
    supervisor.send(:expire_operational_authorizations)

    assert_predicate authorization.reload, :revoked_at?
  ensure
    Current.reset
  end

  test "live supervisor tick sweeps elapsed shared permission requests after mutation expiry" do
    session = create_runtime_session
    grant = session.issue_runtime_grant!.grant
    message = Agent::Message.create!(
      household: grant.household,
      person: grant.person,
      conversation: grant.conversation,
      agent_session: session,
      role: "user",
      body: "Do not dispatch an expired capture",
      body_digest: Digest::SHA256.hexdigest("Do not dispatch an expired capture")
    )
    submission = Agent::KnowledgeSubmission.propose!(
      grant: grant,
      message: message,
      content: "Expired household observation",
      requested_intent: "capture",
      request_id: "supervisor-expired-knowledge",
      deadline_at: 1.second.ago
    )
    request = submission.permission_request
    lorester_calls = []
    fake = Object.new
    fake.define_singleton_method(:submit) { |**arguments| lorester_calls << arguments }
    Agent::Profile.update_all(enabled: false)

    with_stubbed_method(Lorester::Client, :new, fake) do
      with_instance_root do |directory|
        supervisor = Acp::Supervisor.new(instance_root: directory)
        supervisor.start!
        supervisor.tick

        assert_equal "expired", request.reload.status
        assert_nil request.decision
        assert_equal "pending", submission.reload.status
        assert_nil submission.lorester_submission_id
        assert_empty lorester_calls
      ensure
        supervisor&.shutdown!
      end
    end
  end

  test "shared permission sweep runs after mutation proposal sweep" do
    order = []
    mutation_scope = Object.new
    mutation_scope.define_singleton_method(:where) { |**_conditions| self }
    mutation_scope.define_singleton_method(:find_each) { |&_block| order << :mutation_proposals }
    permission_scope = Object.new
    permission_scope.define_singleton_method(:find_each) { |&_block| order << :permission_requests }
    permission_where = ->(**_conditions) { permission_scope }
    supervisor = Acp::Supervisor.new(instance_root: Dir.pwd)

    with_stubbed_method(Agent::MutationProposal, :pending, mutation_scope) do
      with_stubbed_method(Agent::PermissionRequest, :where, permission_where) do
        supervisor.send(:expire_pending_mutations)
      end
    end

    assert_equal %i[mutation_proposals permission_requests], order
  end

  test "authorization rotation detaches an attached ACP session" do
    with_supervisor do |supervisor|
      agent_session = supervisor.start_session(conversation: agent_conversations(:active))
      agent_session.update!(mcp_authorization_status: "reauthorization_required")

      supervisor.send(:rotate_stale_authorizations)

      assert_equal "disconnected", agent_session.reload.status
      assert_raises(Acp::Supervisor::Error) { supervisor.connection_for(agent_session) }
      assert agent_session.grants.all?(&:revoked_at?)
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
    def stage_delete_proposal(grant, meal, idempotency_key, deadline_at)
      arguments = { id: meal.id }
      Agent::MutationProposal.propose!(
        grant: grant, capability: "health.write", operation: "delete_meal", arguments: arguments, preview: {},
        expected_state: Agent::Mutation::Operations.expected_state(operation: "delete_meal", arguments: arguments, proposal: grant),
        idempotency_key: idempotency_key, deadline_at: deadline_at
      )
    end

    def permission_params(agent_session, meal, idempotency_key, tool_call_id)
      {
        "sessionId" => agent_session.external_session_id,
        "toolCall" => {
          "toolCallId" => tool_call_id,
          "title" => "delete_meal",
          "rawInput" => { "id" => meal.id, "idempotency_key" => idempotency_key }
        },
        "options" => [
          { "optionId" => "allow", "kind" => "allow_once" },
          { "optionId" => "reject", "kind" => "reject_once" }
        ]
      }
    end

    def with_supervisor(mode: "normal", timeout: 2, recovery_backoffs: [ 0, 0, 0 ],
      on_fatal: ->(_session, _error) { }, connection_factory: nil, runtime_capability_groups: nil,
      acceptance_environment: nil)
      with_instance_root do |root|
        configure_profile
        supervisor = Acp::Supervisor.new(
          instance_root: root,
          connection_factory: connection_factory || self.connection_factory(modes: [ mode ], timeout: timeout),
          recovery_backoffs: recovery_backoffs,
          on_fatal: on_fatal,
          runtime_capability_groups: runtime_capability_groups,
          acceptance_environment: acceptance_environment
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
        executable_path: RbConfig.ruby,
        agent_version: "1.0.0"
      )
      agent_sessions(:connected).update!(external_session_id: "fake-session-1")
    end

    def with_instance_root
      Dir.mktmpdir("hearth-supervisor") do |root|
        Hearth::Instance.new(root).initialize!
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
