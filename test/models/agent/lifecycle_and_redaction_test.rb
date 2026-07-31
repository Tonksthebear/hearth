require "test_helper"

class Agent::LifecycleAndRedactionTest < ActiveSupport::TestCase
  test "ACP session follows declared transitions and preserves transcript on disconnect" do
    agent_session = agent_sessions(:connected)
    message = agent_messages(:prompt)

    agent_session.disconnect!

    assert_equal "disconnected", agent_session.status
    assert_predicate agent_session.disconnected_at, :present?
    assert Agent::Message.exists?(message.id)

    agent_session.connect!
    agent_session.close!
    assert_equal "closed", agent_session.status
    assert_raises(ActiveRecord::RecordInvalid) { agent_session.connect! }
  end

  test "ACP session authentication status uses the installation vocabulary" do
    agent_session = agent_sessions(:connected)
    agent_session.authentication_status = "totally-bogus"

    assert_not agent_session.valid?
    assert_includes agent_session.errors[:authentication_status], "is not included in the list"
    assert_raises(ActiveRecord::StatementInvalid) do
      Agent::Session.where(id: agent_session.id).update_all(authentication_status: "totally-bogus")
    end
  end

  test "permission request records one actor-attributed body-free decision audit" do
    request = agent_permission_requests(:pending)

    decision = request.decide!(outcome: "denied", by: users(:one), reason: "Not this time")

    assert_equal "denied", request.reload.status
    assert_equal users(:one), decision.decided_by
    event = Agent::AuditEvent.order(:id).last
    assert_equal "permission.denied", event.event_type
    assert_equal request.input_digest, event.body_digest
    assert_equal({ "tool_name" => "health_lookup", "capability" => "health.read" }, event.metadata)
    refute_includes event.metadata.to_json, request.input_body
    assert_raises(ActiveRecord::RecordInvalid) do
      request.decide!(outcome: "approved", by: users(:one))
    end
  end

  test "permission decision rejects an actor outside the request household" do
    decision = agent_permission_decisions(:approved)
    decision.decided_by_id = 0

    assert_not decision.valid?
    assert_includes decision.errors[:decided_by], "must belong to this household"
  end

  test "conversation and tool activity reject undeclared lifecycle transitions" do
    conversation = agent_conversations(:active)
    grant = agent_grants(:active)
    activity = Agent::ToolActivity.create!(
      household: households(:home),
      person: people(:two),
      conversation: conversation,
      agent_session: agent_sessions(:connected),
      tool_name: "health_lookup",
      capability: "health.read",
      input_body: "{}"
    )

    conversation.close!
    assert_equal "closed", conversation.status
    assert_equal "closed", agent_sessions(:connected).reload.status
    assert_predicate grant.reload, :revoked_at?
    assert_raises(ActiveRecord::RecordInvalid) { activity.succeed!(output_body: "{}", output_tokens: 1) }

    activity.start!
    activity.succeed!(output_body: '{"status":"ok"}', output_tokens: 4)
    assert_equal "succeeded", activity.status
    assert_predicate activity.output_digest, :present?
  end

  test "closed context rejects new tool activity but accepts late transcript messages" do
    conversation = agent_conversations(:active)
    conversation.close!

    activity = Agent::ToolActivity.new(
      household: households(:home),
      person: people(:two),
      conversation: conversation,
      agent_session: agent_sessions(:connected),
      tool_name: "health_lookup",
      capability: "health.read",
      input_body: "{}"
    )
    assert_not activity.valid?
    assert_includes activity.errors[:conversation], "must be active"
    assert_includes activity.errors[:agent_session], "must be starting or connected"

    message = Agent::Message.new(
      household: households(:home),
      person: people(:two),
      conversation: conversation,
      agent_session: agent_sessions(:connected),
      role: "agent",
      body: "Late final response"
    )
    assert_predicate message, :valid?
  end

  test "permission and tool cancellation plus session and tool failure are terminal" do
    request = agent_permission_requests(:pending)
    request.cancel!
    assert_equal "cancelled", request.status
    assert_raises(ActiveRecord::RecordInvalid) { request.cancel! }

    activity = Agent::ToolActivity.create!(
      household: households(:home),
      person: people(:two),
      conversation: agent_conversations(:active),
      agent_session: agent_sessions(:connected),
      tool_name: "health_lookup",
      capability: "health.read",
      input_body: "{}"
    )
    activity.start!
    activity.fail!(output_body: '{"error":"unavailable"}')
    assert_equal "failed", activity.status
    assert_raises(ActiveRecord::RecordInvalid) { activity.cancel! }

    agent_sessions(:connected).fail!
    assert_equal "failed", agent_sessions(:connected).status
  end

  test "message redaction removes application body and retains digest envelope" do
    message = agent_messages(:prompt)
    original_body = message.body
    original_digest = message.body_digest

    message.redact!(by: users(:one), reason: "Operator request")

    assert_nil message.reload.body
    assert_equal original_digest, message.body_digest
    assert_equal "Operator request", message.redaction_reason
    event = Agent::AuditEvent.order(:id).last
    assert_equal "message.redacted", event.event_type
    assert_equal users(:one), event.actor
    assert_equal({ "reason" => "Operator request" }, event.metadata)
    refute_includes event.attributes.to_json, original_body
  end

  test "redaction cannot be reversed or have its digest envelope altered" do
    message = agent_messages(:prompt)
    message.redact!(by: users(:one), reason: "Operator request")
    digest = message.body_digest

    assert_raises(ActiveRecord::RecordInvalid) do
      message.update!(body: "restored", redacted_at: nil, redaction_reason: nil)
    end
    assert_raises(ActiveRecord::RecordInvalid) { message.update!(body_digest: "0" * 64) }

    message.reload
    assert_nil message.body
    assert_predicate message, :redacted_at?
    assert_equal digest, message.body_digest
  end

  test "tool redaction removes input and output bodies from model and audit projection" do
    activity = agent_tool_activities(:completed)
    input = activity.input_body
    output = activity.output_body

    activity.redact!(by: users(:one), reason: "Sensitive health result")

    assert_nil activity.reload.input_body
    assert_nil activity.output_body
    event = Agent::AuditEvent.order(:id).last
    refute_includes event.attributes.to_json, input
    refute_includes event.attributes.to_json, output
  end

  test "audit scopes enforce household person and conversation context" do
    event = agent_audit_events(:conversation_started)

    assert_equal [ event ], Agent::AuditEvent.for_household(households(:home)).for_person(people(:two)).to_a
    assert_equal [ event ], Agent::AuditEvent.for_conversation(agent_conversations(:active)).to_a
    assert_empty Agent::AuditEvent.for_person(people(:one))
  end
end
