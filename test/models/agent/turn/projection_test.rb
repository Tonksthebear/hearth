require "test_helper"

class Agent::Turn::ProjectionTest < ActiveSupport::TestCase
  setup do
    @turn = agent_conversations(:active).enqueue_turn!(
      body: "Project updates", browser_session: sessions(:browser), idempotency_key: "projection-turn"
    )
    @turn.attach!(agent_sessions(:connected))
    @projection = Agent::Turn::Projection.new(@turn)
  end

  test "message chunks create on first nonempty content and then append" do
    apply_update("agent_message_chunk", "messageId" => "answer-1", "content" => { "type" => "text", "text" => "" })
    assert_nil Agent::Message.find_by(external_id: "answer-1")

    apply_update("agent_message_chunk", "messageId" => "answer-1", "content" => { "type" => "text", "text" => "**Hello**" })
    apply_update("agent_message_chunk", "messageId" => "answer-1", "content" => { "type" => "text", "text" => " world" })

    message = Agent::Message.find_by!(external_id: "answer-1")
    assert_equal "**Hello** world", message.body
    assert_equal Digest::SHA256.hexdigest(message.body), message.body_digest
    assert_includes message.rendered_body, "<strong>Hello</strong>"
  end

  test "ACP activities are digest only and plan updates replace complete state" do
    apply_update("tool_call", {
      "toolCallId" => "tool-1", "title" => "Search records", "kind" => "search",
      "status" => "in_progress", "rawInput" => { "private" => "not persisted" }
    })
    activity = Agent::ToolActivity.find_by!(external_id: "tool-1")
    assert_equal "acp", activity.source
    assert_equal "acp.tool", activity.capability
    assert_nil activity.tool_name
    assert_nil activity.input_body
    assert_predicate activity, :redacted_at?

    apply_update("plan", "entries" => [ { "content" => "First", "status" => "pending" } ])
    apply_update("plan", "entries" => [ { "content" => "Replacement", "status" => "completed" } ])
    assert_equal [ { "content" => "Replacement", "status" => "completed" } ], @turn.conversation.plan.reload.entries
  end

  test "citations persist safe provenance and reject unsafe URLs" do
    apply_update("citation", "id" => "cite-1", "title" => "Household log", "sourceKind" => "hearth_fact")
    citation = Agent::Citation.find_by!(external_id: "cite-1")
    assert_equal "hearth_fact", citation.source_kind

    assert_raises(ActiveRecord::RecordInvalid) do
      apply_update("citation", "id" => "cite-2", "title" => "Unsafe", "url" => "javascript:alert(1)")
    end
  end

  private
    def apply_update(kind, attributes)
      @projection.apply!({
        "method" => "session/update",
        "params" => {
          "sessionId" => agent_sessions(:connected).external_session_id,
          "update" => attributes.merge("sessionUpdate" => kind)
        }
      })
    end
end
