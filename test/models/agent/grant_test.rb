require "test_helper"

class Agent::GrantTest < ActiveSupport::TestCase
  setup do
    Current.session = sessions(:browser)
    Current.household = households(:home)
    Current.person = people(:two)
  end

  teardown { Current.reset }

  test "issues the raw credential once while persisting only locator and digest" do
    credential = issue_grant
    grant = credential.grant

    assert_match(/\A[0-9a-f]{32}\.[A-Za-z0-9_-]+\z/, credential.bearer)
    assert_equal 64, grant.token_digest.length
    refute_includes grant.attributes.values, credential.bearer
    refute_includes grant.attributes.values, credential.bearer.split(".", 2).last
    assert_equal "#<Agent::Grant::Credential [REDACTED]>", credential.inspect
    assert_raises(TypeError) { credential.as_json }
    event = Agent::AuditEvent.where(subject_type: "Agent::Grant", subject_id: grant.id).sole
    assert_equal "grant.issued", event.event_type
    assert_equal [ "health_read" ], event.metadata["capability_groups"]
  end

  test "verifies exact persisted context without consulting mutable current person" do
    credential = issue_grant
    Current.person = people(:one)

    verified = Agent::Grant.verify(
      bearer: credential.bearer,
      browser_session: sessions(:browser),
      conversation: agent_conversations(:active),
      agent_session: agent_sessions(:connected),
      capability: "health.read"
    )

    assert_equal credential.grant, verified

    other_conversation = Agent::Conversation.create!(
      household: households(:home),
      person: people(:one),
      profile: agent_profiles(:hearth),
      title: "Other person"
    )
    assert_nil Agent::Grant.verify(
      bearer: credential.bearer,
      browser_session: sessions(:browser),
      conversation: other_conversation,
      agent_session: agent_sessions(:connected),
      capability: "health.read"
    )
  end

  test "runtime grant authenticates from its bearer without browser context" do
    session = create_runtime_session
    credential = session.issue_runtime_grant!

    assert_nil credential.grant.browser_session_id
    assert_nil credential.grant.issued_by_id
    assert_equal credential.grant, Agent::Grant.authenticate(bearer: credential.bearer)
    assert_nil Agent::Grant.authenticate(bearer: "#{credential.grant.token_locator}.wrong")
    event = Agent::AuditEvent.where(subject_type: "Agent::Grant", subject_id: credential.grant.id).sole
    assert_equal "acp_runtime", event.metadata["source"]
  end

  test "runtime bearer authentication rejects every inactive or mismatched context" do
    assert_nil Agent::Grant.authenticate(bearer: "malformed")

    credential = runtime_credential
    assert_nil Agent::Grant.authenticate(bearer: credential.bearer, at: credential.grant.expires_at)
    assert_equal "reauthorization_required", credential.grant.agent_session.reload.mcp_authorization_status

    credential = runtime_credential
    credential.grant.revoke!(reason: "test")
    assert_nil Agent::Grant.authenticate(bearer: credential.bearer)

    credential = runtime_credential
    credential.grant.update_column(:capability_groups, [ "retired_group" ])
    assert_nil Agent::Grant.authenticate(bearer: credential.bearer)

    credential = runtime_credential
    credential.grant.conversation.update_column(:status, "closed")
    assert_nil Agent::Grant.authenticate(bearer: credential.bearer)
    credential.grant.conversation.update_column(:status, "active")

    credential = runtime_credential
    credential.grant.agent_session.update_column(:status, "closed")
    assert_nil Agent::Grant.authenticate(bearer: credential.bearer)

    credential = runtime_credential
    credential.grant.update_column(:person_id, people(:one).id)
    assert_nil Agent::Grant.authenticate(bearer: credential.bearer)

    credential = runtime_credential
    other_conversation = Agent::Conversation.create!(
      household: households(:home),
      person: people(:two),
      profile: agent_profiles(:hearth),
      title: "Authentication mismatch"
    )
    credential.grant.update_column(:conversation_id, other_conversation.id)
    assert_nil Agent::Grant.authenticate(bearer: credential.bearer)

    credential = runtime_credential
    credential.grant.agent_session.update_column(:person_id, people(:one).id)
    assert_nil Agent::Grant.authenticate(bearer: credential.bearer)

    credential = issue_grant
    other_browser_session = users(:two).sessions.create!
    credential.grant.update_column(:browser_session_id, other_browser_session.id)
    assert_nil Agent::Grant.authenticate(bearer: credential.bearer)

    credential = runtime_credential
    credential.grant.update_column(:calls_used, credential.grant.calls_limit)
    assert_nil Agent::Grant.authenticate(bearer: credential.bearer)
    assert_equal "reauthorization_required", credential.grant.agent_session.reload.mcp_authorization_status

    credential = runtime_credential
    credential.grant.update_column(:output_tokens_used, credential.grant.output_tokens_limit)
    assert_nil Agent::Grant.authenticate(bearer: credential.bearer)
    assert_equal "reauthorization_required", credential.grant.agent_session.reload.mcp_authorization_status
  end

  test "an expired superseded grant leaves a session authorized by its usable replacement" do
    session = create_runtime_session
    expired = session.issue_runtime_grant!
    replacement = session.issue_runtime_grant!
    expired.grant.update!(expires_at: 1.minute.from_now)
    replacement.grant.update!(expires_at: 5.minutes.from_now)

    assert_nil Agent::Grant.authenticate(bearer: expired.bearer, at: expired.grant.expires_at)
    assert_equal "authorized", session.reload.mcp_authorization_status
    assert_equal replacement.grant, Agent::Grant.authenticate(bearer: replacement.bearer)
  end

  test "denies wrong secret expiry revocation and unknown capability" do
    credential = issue_grant
    args = {
      browser_session: sessions(:browser),
      conversation: agent_conversations(:active),
      agent_session: agent_sessions(:connected)
    }

    assert_nil Agent::Grant.verify(bearer: "#{credential.grant.token_locator}.wrong", capability: "health.read", **args)
    assert_nil Agent::Grant.verify(bearer: credential.bearer, capability: "health.unknown", **args)
    other_browser_session = users(:two).sessions.create!
    assert_nil Agent::Grant.verify(
      bearer: credential.bearer,
      browser_session: other_browser_session,
      conversation: agent_conversations(:active),
      agent_session: agent_sessions(:connected),
      capability: "health.read"
    )
    assert_nil Agent::Grant.verify(
      bearer: credential.bearer,
      capability: "health.read",
      at: credential.grant.expires_at,
      **args
    )

    credential.grant.revoke!(reason: "Operator action", by: users(:one))
    assert_nil Agent::Grant.verify(bearer: credential.bearer, capability: "health.read", **args)
  end

  test "denies a valid bearer when authenticated browser context is missing" do
    credential = issue_grant

    assert_nil Agent::Grant.verify(
      bearer: credential.bearer,
      browser_session: nil,
      conversation: agent_conversations(:active),
      agent_session: agent_sessions(:connected),
      capability: "health.read"
    )
  end

  test "denies unknown capability groups at issuance" do
    assert_raises(ActiveRecord::RecordInvalid) do
      Agent::Grant.issue!(
        conversation: agent_conversations(:active),
        agent_session: agent_sessions(:connected),
        capability_groups: [ "future_plugin_group" ],
        expires_at: 10.minutes.from_now
      )
    end
  end

  test "resolves capability group membership at authorization time" do
    credential = issue_grant
    mapping = { "health_read" => %w[ health.changed ] }.freeze

    original = Agent::Grant::CAPABILITY_GROUPS
    Agent::Grant.send(:remove_const, :CAPABILITY_GROUPS)
    Agent::Grant.const_set(:CAPABILITY_GROUPS, mapping)
    begin
      assert credential.grant.allows_capability?("health.changed")
      assert_not credential.grant.allows_capability?("health.read")
    ensure
      Agent::Grant.send(:remove_const, :CAPABILITY_GROUPS)
      Agent::Grant.const_set(:CAPABILITY_GROUPS, original)
    end
  end

  test "guarded update consumes budgets once and rejects exhausted replay without mutation" do
    grant = agent_grants(:active)

    assert_equal 1, grant.consume(calls: 1, output_tokens: 6)
    assert_equal [ 1, 6 ], grant.reload.values_at(:calls_used, :output_tokens_used)
    assert_equal 0, grant.consume(calls: 1, output_tokens: 5)
    assert_equal [ 1, 6 ], grant.reload.values_at(:calls_used, :output_tokens_used)
    assert_equal 1, grant.consume(calls: 1, output_tokens: 4)
    assert_equal 0, grant.consume(calls: 1, output_tokens: 0)
    assert_equal [ 2, 10 ], grant.reload.values_at(:calls_used, :output_tokens_used)
  end

  test "guarded update rejects revoked and expired grants" do
    revoked = agent_grants(:active)
    revoked.revoke!(reason: "Test")
    assert_equal 0, revoked.consume

    expired = issue_grant.grant
    assert_equal 0, expired.consume(at: expired.expires_at)
  end

  test "ACP disconnect revokes grants without deleting transcript or audit history" do
    grant = agent_grants(:active)
    message = agent_messages(:prompt)
    audit_event = agent_audit_events(:conversation_started)

    agent_sessions(:connected).disconnect!

    assert_predicate grant.reload, :revoked_at?
    event = Agent::AuditEvent.where(subject_type: "Agent::Grant", subject_id: grant.id).order(:id).last
    assert_equal "grant.revoked", event.event_type
    assert_equal "agent disconnected", event.metadata["reason"]
    assert_equal "reauthorization_required", agent_sessions(:connected).reload.mcp_authorization_status
    assert Agent::Message.exists?(message.id)
    assert Agent::AuditEvent.exists?(audit_event.id)
  end

  test "operator revocation bypasses obsolete capability validation and remains audited" do
    grant = agent_grants(:active)

    without_health_read_capability do
      grant.revoke!(reason: "Operator action", by: users(:one))
    end

    assert_predicate grant.reload, :revoked_at?
    event = Agent::AuditEvent.where(subject_type: "Agent::Grant", subject_id: grant.id).order(:id).last
    assert_equal "grant.revoked", event.event_type
    assert_equal "Operator action", event.metadata["reason"]
  end

  test "ACP close revokes grants that no longer pass capability validation" do
    grant = agent_grants(:active)

    without_health_read_capability { agent_sessions(:connected).close! }

    assert_equal "closed", agent_sessions(:connected).reload.status
    assert_predicate grant.reload, :revoked_at?
    assert_equal "grant.revoked",
      Agent::AuditEvent.where(subject_type: "Agent::Grant", subject_id: grant.id).order(:id).last.event_type
  end

  test "browser logout revokes grants that no longer pass capability validation" do
    grant = agent_grants(:active)
    browser_session = sessions(:browser)

    without_health_read_capability { browser_session.destroy! }

    assert_not Session.exists?(browser_session.id)
    assert_predicate grant.reload, :revoked_at?
    assert_equal "grant.revoked",
      Agent::AuditEvent.where(subject_type: "Agent::Grant", subject_id: grant.id).order(:id).last.event_type
  end

  test "closed conversations and terminal sessions reject new grants" do
    agent_conversations(:active).close!

    error = assert_raises(ActiveRecord::RecordInvalid) { issue_grant }
    assert_includes error.record.errors[:conversation], "must be active"
    assert_includes error.record.errors[:agent_session], "must be starting or connected"
  end

  private
    def runtime_credential
      create_runtime_session.issue_runtime_grant!
    end

    def issue_grant
      Agent::Grant.issue!(
        conversation: agent_conversations(:active),
        agent_session: agent_sessions(:connected),
        capability_groups: [ "health_read" ],
        expires_at: 10.minutes.from_now,
        calls_limit: 3,
        output_tokens_limit: 100
      )
    end

    def without_health_read_capability
      original = Agent::Grant::CAPABILITY_GROUPS
      Agent::Grant.send(:remove_const, :CAPABILITY_GROUPS)
      Agent::Grant.const_set(:CAPABILITY_GROUPS, {}.freeze)
      yield
    ensure
      Agent::Grant.send(:remove_const, :CAPABILITY_GROUPS)
      Agent::Grant.const_set(:CAPABILITY_GROUPS, original)
    end
end
