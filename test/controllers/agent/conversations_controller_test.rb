require "test_helper"

class Agent::ConversationsControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:two) }

  test "renders scoped conversations and creates one with an enabled household profile" do
    get agent_conversations_path
    assert_response :success
    assert_select "h1", text: /Conversations for #{people(:two).name}/

    assert_difference("Agent::Conversation.count", 1) do
      post agent_conversations_path, params: {
        agent_conversation: { profile_id: agent_profiles(:hearth).id, title: "Recovery review" }
      }
    end
    assert_redirected_to agent_conversation_path(Agent::Conversation.order(:id).last)
  end

  test "conversation show reconstructs persisted projections" do
    get agent_conversation_path(agent_conversations(:active))

    assert_response :success
    assert_select "#agent_messages"
    assert_select "#agent_activities"
    assert_select "#agent_plan"
    assert_select "#agent_citations"
    assert_select "#agent_messages[aria-live]", count: 0
    assert_select "#agent_turn_status[role='status'][aria-live='polite']"
    assert_select "form[action='#{agent_conversation_turns_path(agent_conversations(:active))}']"
    assert_select "h2", text: "Health information, not medical advice"
  end

  test "conversation forms keep explicit labels" do
    get new_agent_conversation_path
    assert_response :success
    assert_select "label[for='agent_conversation_profile_id']", text: "Agent"
    assert_select "label[for='agent_conversation_title']", text: "Conversation title"

    get agent_conversation_path(agent_conversations(:active))
    assert_select "label[for='turn_body']", text: "Message the coach"
  end

  test "other person conversation is not visible" do
    other = Agent::Conversation.create!(
      household: households(:home), person: people(:one), profile: agent_profiles(:hearth), title: "Private"
    )

    get agent_conversation_path(other)

    assert_response :not_found
  end
end
