require "test_helper"

class SessionTest < ActiveSupport::TestCase
  test "destroy revokes scoped agent grants before nullifying browser session" do
    browser_session = sessions(:browser)
    grant = agent_grants(:active)

    browser_session.destroy!

    assert_predicate grant.reload, :revoked_at?
    assert_equal "browser session ended", grant.revocation_reason
    assert_nil grant.browser_session_id
    event = Agent::AuditEvent.where(subject_type: "Agent::Grant", subject_id: grant.id).order(:id).last
    assert_equal "grant.revoked", event.event_type
    assert_equal "browser session ended", event.metadata["reason"]
    assert Agent::Session.exists?(agent_sessions(:connected).id)
  end
end
