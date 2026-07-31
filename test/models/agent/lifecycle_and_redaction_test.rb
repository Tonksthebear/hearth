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

  test "conversation and tool activity reject undeclared lifecycle transitions" do
    conversation = agent_conversations(:active)
    conversation.close!
    assert_equal "closed", conversation.status

    activity = Agent::ToolActivity.create!(
      household: households(:home),
      person: people(:two),
      conversation: conversation,
      agent_session: agent_sessions(:connected),
      tool_name: "health_lookup",
      capability: "health.read",
      input_body: "{}"
    )
    assert_raises(ActiveRecord::RecordInvalid) { activity.succeed!(output_body: "{}", output_tokens: 1) }

    activity.start!
    activity.succeed!(output_body: '{"status":"ok"}', output_tokens: 4)
    assert_equal "succeeded", activity.status
    assert_predicate activity.output_digest, :present?
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
