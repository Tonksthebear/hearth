require "test_helper"

class Agent::TurnTest < ActiveSupport::TestCase
  test "conversation turn eligibility combines lifecycle and profile state" do
    conversation = agent_conversations(:active)

    assert_predicate conversation, :accepts_turns?
    conversation.profile.update!(enabled: false)
    refute_predicate conversation, :accepts_turns?
    conversation.profile.update!(enabled: true)
    conversation.update!(status: "closed", closed_at: Time.current)
    refute_predicate conversation, :accepts_turns?
  end

  test "enqueue persists the exact user message and one idempotent pending turn" do
    conversation = agent_conversations(:active)
    browser_session = sessions(:browser)

    first = conversation.enqueue_turn!(body: "Use my recorded week.", browser_session: browser_session, idempotency_key: "turn-once")
    duplicate = conversation.enqueue_turn!(body: "This duplicate must not persist.", browser_session: browser_session, idempotency_key: "turn-once")

    assert_equal first, duplicate
    assert_equal "pending", first.status
    assert_equal "Use my recorded week.", first.user_message.body
    assert_equal 1, conversation.turns.where(idempotency_key: "turn-once").count
    assert_equal 1, conversation.messages.where(body: [ "Use my recorded week.", "This duplicate must not persist." ]).count
  end

  test "only one owner claims a pending turn" do
    turn = agent_conversations(:active).enqueue_turn!(
      body: "Claim once", browser_session: sessions(:browser), idempotency_key: "single-claim"
    )

    claimed = Agent::Turn.claim_next!(owner: "runtime-one")
    second = Agent::Turn.claim_next!(owner: "runtime-two")

    assert_equal turn, claimed
    assert_nil second
    assert_equal "runtime-one", turn.reload.claimed_by
  end

  test "stale claims recover only before dispatch" do
    recoverable = agent_conversations(:active).enqueue_turn!(
      body: "Recover me", browser_session: sessions(:browser), idempotency_key: "recoverable-claim"
    )
    recoverable.update_columns(status: "claimed", claimed_by: "gone", lease_expires_at: 1.second.ago)
    ambiguous = agent_conversations(:active).enqueue_turn!(
      body: "Do not replay me", browser_session: sessions(:browser), idempotency_key: "ambiguous-claim"
    )
    ambiguous.update_columns(status: "running", claimed_by: "gone", dispatched_at: 2.seconds.ago, lease_expires_at: 1.second.ago)

    Agent::Turn.recover_stale_claims!

    assert_equal "pending", recoverable.reload.status
    assert_equal "failed", ambiguous.reload.status
    assert_match(/submit a new turn/, ambiguous.error_message)
  end

  test "cancellation and completion are idempotent" do
    turn = agent_conversations(:active).enqueue_turn!(
      body: "Cancel me", browser_session: sessions(:browser), idempotency_key: "cancel-turn"
    )
    Agent::Turn.claim_next!(owner: "runtime")
    turn.reload.dispatch!

    turn.request_cancel!.request_cancel!
    turn.succeed!(stop_reason: "cancelled")
    turn.succeed!(stop_reason: "end_turn")

    assert_equal "cancelled", turn.reload.status
    assert_equal "cancelled", turn.stop_reason
  end
end
