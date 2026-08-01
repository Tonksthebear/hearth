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
    @projection.flush!

    message = Agent::Message.find_by!(external_id: "answer-1")
    assert_equal "**Hello** world", message.body
    assert_equal Digest::SHA256.hexdigest(message.body), message.body_digest
    assert_includes message.rendered_body, "<strong>Hello</strong>"
  end

  test "ACP activities are digest only and plan updates replace complete state" do
    broadcasts = capture_turbo_stream_broadcasts(@turn.conversation) do
      apply_update("tool_call", {
        "toolCallId" => "tool-1", "title" => "Search records", "kind" => "search",
        "status" => "in_progress", "rawInput" => { "private" => "not persisted" }
      })
      apply_update("tool_call_update", "toolCallId" => "tool-1", "status" => "completed")
      @projection.flush!
      apply_update("tool_call_update", "toolCallId" => "tool-1", "status" => "failed")
      @projection.flush!
    end
    activity = Agent::ToolActivity.find_by!(external_id: "tool-1")
    assert_equal "acp", activity.source
    assert_equal "acp.tool", activity.capability
    assert_nil activity.tool_name
    assert_nil activity.input_body
    assert_predicate activity, :redacted_at?
    assert_equal "Search records", activity.display_title
    assert_equal "search", activity.kind
    assert_equal "failed", activity.status
    assert_equal 2, broadcasts.count { |stream| stream["target"] == "agent_activities" }
    assert broadcasts.none? { |stream| stream["target"] == ActionView::RecordIdentifier.dom_id(activity) }

    apply_update("plan", "entries" => [ { "content" => "First", "status" => "pending" } ])
    apply_update("plan", "entries" => [ { "content" => "Replacement", "status" => "completed" } ])
    assert_equal [ { "content" => "Replacement", "status" => "completed" } ], @turn.conversation.plan.reload.entries
  end

  test "citations persist safe provenance and report unsafe URLs without failing projection" do
    apply_update("citation", "id" => "cite-1", "title" => "Household log", "sourceKind" => "hearth_fact")
    citation = Agent::Citation.find_by!(external_id: "cite-1")
    assert_equal "hearth_fact", citation.source_kind

    apply_update("citation", "id" => "cite-2", "title" => "Unsafe", "url" => "javascript:alert(1)")

    assert_nil Agent::Citation.find_by(external_id: "cite-2")
    assert_match(/Ignored a malformed ACP citation update/, @turn.reload.warning_message)
  end

  test "many small chunks are buffered into one persistence and broadcast cycle" do
    broadcasts = capture_turbo_stream_broadcasts(@turn.conversation) do
      100.times do
        apply_update("agent_message_chunk", "messageId" => "buffered-answer", "content" => { "type" => "text", "text" => "x" })
      end
      assert_nil Agent::Message.find_by(external_id: "buffered-answer")
      @projection.flush!
      apply_update("agent_message_chunk", "messageId" => "buffered-answer", "content" => { "type" => "text", "text" => "y" })
      @projection.flush!
    end

    message = Agent::Message.find_by!(external_id: "buffered-answer")
    assert_equal "#{'x' * 100}y", message.body
    assert_equal 2, broadcasts.count { |stream| stream["target"] == "agent_messages" }
    assert broadcasts.none? { |stream| stream["target"] == ActionView::RecordIdentifier.dom_id(message) }
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
