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

  test "ACP disconnect revokes grants without deleting transcript or audit history" do
    grant = agent_grants(:active)
    message = agent_messages(:prompt)
    audit_event = agent_audit_events(:conversation_started)

    agent_sessions(:connected).disconnect!

    assert_predicate grant.reload, :revoked_at?
    assert Agent::Message.exists?(message.id)
    assert Agent::AuditEvent.exists?(audit_event.id)
  end

  private
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
end
