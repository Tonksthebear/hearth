require "test_helper"

class Agent::SessionTest < ActiveSupport::TestCase
  test "pending sessions allow no external id and are not recoverable" do
    session = agent_sessions(:connected)
    session.grants.update_all(revoked_at: Time.current, revocation_reason: "test")
    session.update!(status: "starting", external_session_id: nil)

    assert_predicate session, :valid?
    assert_not Agent::Session.recoverable.exists?(session.id)

    session.bind_external_session!("bound-once")
    assert Agent::Session.recoverable.exists?(session.id)
    assert_raises(ActiveRecord::RecordInvalid) { session.bind_external_session!("twice") }
  end

  test "connected and closed sessions require an external id" do
    session = agent_sessions(:connected)
    session.external_session_id = nil

    assert_not session.valid?
    assert_includes session.errors[:external_session_id], "can't be blank"
  end
end
