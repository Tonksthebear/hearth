require "test_helper"

class Agent::OperationalAuthorizationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:two)
    @agent_session = Agent::Session.create!(
      household: households(:home),
      person: people(:two),
      conversation: agent_conversations(:active),
      installation: agent_installations(:local),
      browser_session: Current.session,
      external_session_id: "controller-operational-session",
      status: "connected",
      authentication_status: "authenticated",
      mcp_authorization_status: "authorized"
    )
  end

  test "authenticated exact-context user enables and disables operational access" do
    get root_path
    assert_select "[data-agent-operational-access]", text: /read-only/

    post agent_operational_authorizations_path, params: {
      agent_session_id: @agent_session.id,
      reason: "Daily operations"
    }
    assert_redirected_to root_path

    authorization = @agent_session.operational_authorizations.last
    assert_equal users(:two), authorization.authorized_by
    get root_path
    assert_select "[data-agent-operational-access]", text: /enabled for #{people(:two).name}/

    delete agent_operational_authorization_path(authorization)
    assert_redirected_to root_path
    assert_not_nil authorization.reload.revoked_at
  end

  test "another browser session cannot enable access" do
    other_session = sessions(:browser)

    post agent_operational_authorizations_path, params: {
      agent_session_id: agent_sessions(:connected).id,
      reason: "Wrong browser"
    }

    assert_response :not_found
    assert_equal other_session, agent_sessions(:connected).browser_session
  end
end
