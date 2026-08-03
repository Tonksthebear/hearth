require "test_helper"

class Agent::SetupRequest::RuntimeTest < ActiveSupport::TestCase
  FakeProbe = Data.define(:version)

  class FakeCandidate
    attr_reader :observed, :authenticated

    def cli_available? = true
    def cli_version = "cli 1.0"
    def transport_available? = true
    def state_for(household) = Agent::Profile::Certified.new(Agent::Profile::Certified::DEFINITIONS.fetch("grok")).state_for(household)

    def with_probe(instance:)
      yield FakeProbe.new(version: "adapter 2.0")
    end

    def observe_probe!(household:, probe:)
      @observed = [ household, probe ]
    end

    def authenticate_probe!(household:, probe:, method_id:, origin:)
      @authenticated = [ household, probe, method_id, origin ]
    end
  end

  class FakeSupervisor
    attr_reader :ticks
    def initialize = @ticks = 0
    def tick = @ticks += 1
  end

  setup do
    @candidate = FakeCandidate.new
    @supervisor = FakeSupervisor.new
    @runtime = Agent::SetupRequest::Runtime.new(instance: Object.new, supervisor: @supervisor, owner: "runtime")
  end

  test "enable is executed by the runtime and persists only safe detection fields" do
    request = enqueue(action: "enable", key: "runtime-enable")

    with_stubbed_method(Agent::Profile::Certified, :fetch, @candidate) { @runtime.run_next }

    assert_equal "succeeded", request.reload.status
    assert_equal true, request.cli_available
    assert_equal "cli 1.0", request.cli_version
    assert_equal true, request.adapter_available
    assert_equal "adapter 2.0", request.adapter_version
    assert_nil request.dispatched_at
    assert_equal households(:home), @candidate.observed.first
    assert_no_match(/path|token|secret/i, request.attributes.to_json)
  end

  test "authentication passes only the explicitly approved method identity" do
    request = enqueue(action: "authenticate", key: "runtime-auth", authentication_method_id: "browser-login")

    with_stubbed_method(Agent::Profile::Certified, :fetch, @candidate) { @runtime.run_next }

    assert_equal "succeeded", request.reload.status
    assert_predicate request.dispatched_at, :present?
    assert_equal [ households(:home), FakeProbe.new(version: "adapter 2.0"), "browser-login", "web_setting" ],
      @candidate.authenticated
  end

  test "provider errors become allowlisted messages without raw exception text" do
    @candidate.define_singleton_method(:with_probe) { |instance:| raise Acp::Connection::TimeoutError, "token=/secret/path" }
    request = enqueue(action: "enable", key: "runtime-timeout")

    with_stubbed_method(Agent::Profile::Certified, :fetch, @candidate) { @runtime.run_next }

    assert_equal "failed", request.reload.status
    assert_equal "timeout", request.error_category
    assert_no_match(/token|secret|path/, request.error_message)
  end

  test "disable atomically clears approval and revokes live access" do
    assert_disable_revokes(session: agent_sessions(:connected), grant: agent_grants(:active), key: "runtime-disable")
  end

  test "disable revokes an unbound starting session instead of leaving partial state" do
    session = Agent::Session.create!(
      household: households(:home),
      person: people(:two),
      conversation: agent_conversations(:active),
      installation: agent_installations(:local),
      browser_session: sessions(:browser),
      status: "starting",
      external_session_id: nil,
      advertised_capabilities: {},
      authentication_status: "authenticated",
      mcp_authorization_status: "not_configured"
    )
    grant = session.issue_runtime_grant!.grant

    assert_disable_revokes(session: session, grant: grant, key: "runtime-disable-unbound")
  end

  private
    def enqueue(action:, key:, authentication_method_id: nil)
      Agent::SetupRequest.enqueue!(household: households(:home), requested_by: users(:two),
        certified_key: "grok", action: action, authentication_method_id: authentication_method_id,
        idempotency_key: key)
    end


    def assert_disable_revokes(session:, grant:, key:)
      installation = session.installation
      methods_before = installation.authentication_methods.deep_dup
      authorization = Agent::OperationalAuthorization.create!(
        household: session.household,
        person: session.person,
        conversation: session.conversation,
        agent_session: session,
        browser_session: session.browser_session,
        authorized_by: users(:two),
        reason: "Test operational access",
        authorized_at: Time.current,
        expires_at: 10.minutes.from_now,
        revision: 1
      )
      proposal, = Agent::MutationProposal.propose!(
        grant: grant,
        capability: "health.write",
        operation: "test.write",
        arguments: { value: 1 },
        preview: { summary: "Test write" },
        expected_state: {},
        idempotency_key: "#{key}-mutation",
        deadline_at: 5.minutes.from_now
      )
      request = enqueue(action: "disable", key: key)

      with_stubbed_method(Agent::Profile::Certified, :fetch, @candidate) { @runtime.run_next }

      assert_equal "succeeded", request.reload.status
      assert_not session.installation.profile.reload.enabled?
      assert_equal "required", installation.reload.authentication_status
      assert_nil installation.authentication_method_id
      assert_equal methods_before, installation.authentication_methods
      assert_equal "closed", session.reload.status
      assert_predicate grant.reload.revoked_at, :present?
      assert_predicate authorization.reload.revoked_at, :present?
      assert_equal "cancelled", proposal.reload.status
      assert_equal 1, @supervisor.ticks
      assert_nil @candidate.authenticated
    end
end
