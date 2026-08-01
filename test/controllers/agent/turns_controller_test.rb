require "test_helper"

class Agent::TurnsControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:two) }

  test "form submit persists a message and durable turn without constructing a supervisor" do
    replacement = ->(*) { raise "Puma must not construct Acp::Supervisor" }
    with_stubbed_method(Acp::Supervisor, :new, replacement) do
      assert_difference([ "Agent::Message.count", "Agent::Turn.count" ], 1) do
        post agent_conversation_turns_path(agent_conversations(:active)), params: {
          turn: { body: "Review this week", idempotency_key: "controller-turn" }
        }
      end
    end

    turn = Agent::Turn.find_by!(idempotency_key: "controller-turn")
    assert_equal "pending", turn.status
    assert_equal Current.session, turn.browser_session
    assert_redirected_to agent_conversation_path(agent_conversations(:active), anchor: "agent_turn_status")
  end

  test "duplicate browser idempotency key creates one message and turn" do
    params = { turn: { body: "Once", idempotency_key: "controller-duplicate" } }

    2.times { post agent_conversation_turns_path(agent_conversations(:active)), params: params }

    assert_equal 1, Agent::Turn.where(idempotency_key: "controller-duplicate").count
    assert_equal 1, Agent::Message.where(body: "Once").count
  end

  test "another browser cannot cancel the turn" do
    turn = agent_conversations(:active).enqueue_turn!(
      body: "Still running", browser_session: sessions(:browser), idempotency_key: "other-browser-turn"
    )
    Current.session = users(:two).sessions.create!
    ActionDispatch::TestRequest.create.cookie_jar.tap do |jar|
      jar.signed[:session_id] = Current.session.id
      cookies["session_id"] = jar[:session_id]
    end

    post agent_conversation_turn_cancellation_path(agent_conversations(:active), turn)

    assert_response :not_found
    assert_nil turn.reload.cancel_requested_at
  end
end
