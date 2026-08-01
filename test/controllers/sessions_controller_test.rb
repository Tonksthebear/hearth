require "test_helper"

class SessionsControllerTest < ActionDispatch::IntegrationTest
  setup { @user = User.take }

  test "new" do
    get new_session_path
    assert_response :success
  end

  test "create with valid credentials" do
    post session_path, params: { email_address: @user.email_address, password: "password" }

    assert_redirected_to root_path
    assert cookies[:session_id]
    assert Session.exists?
  end

  test "create with invalid credentials" do
    post session_path, params: { email_address: @user.email_address, password: "wrong" }

    assert_redirected_to new_session_path
    assert_nil cookies[:session_id]
  end

  test "destroy" do
    sign_in_as(User.take)
    session_id = Current.session.id

    delete session_path

    assert_redirected_to new_session_path
    assert_empty cookies[:session_id]
    assert_not Session.exists?(session_id)
  end

  test "destroy revokes grants while preserving ACP transcript and audit history" do
    sign_in_as users(:one)
    Current.household = households(:home)
    Current.person = people(:one)
    conversation = Agent::Conversation.create!(
      household: Current.household,
      person: Current.person,
      profile: agent_profiles(:hearth),
      title: "Logout conversation"
    )
    agent_session = Agent::Session.create!(
      household: Current.household,
      person: Current.person,
      conversation: conversation,
      installation: agent_installations(:local),
      browser_session: Current.session,
      external_session_id: "logout-session"
    )
    grant = Agent::Grant.issue!(
      conversation: conversation,
      agent_session: agent_session,
      capability_groups: [ "health_read" ],
      expires_at: 10.minutes.from_now
    ).grant
    message = agent_messages(:prompt)
    audit_event = agent_audit_events(:conversation_started)

    delete session_path

    assert_predicate grant.reload, :revoked_at?
    assert_nil grant.browser_session_id
    assert Agent::Message.exists?(message.id)
    assert Agent::AuditEvent.exists?(audit_event.id)
  end

  test "destroy revokes operational authorization and pending mutations" do
    sign_in_as users(:two)
    Current.household = households(:home)
    Current.person = people(:two)
    agent_session = Agent::Session.create!(
      household: Current.household,
      person: Current.person,
      conversation: agent_conversations(:active),
      installation: agent_installations(:local),
      browser_session: Current.session,
      external_session_id: "logout-operational-session",
      status: "connected",
      authentication_status: "authenticated",
      mcp_authorization_status: "authorized"
    )
    authorization = Agent::OperationalAuthorization.authorize!(agent_session: agent_session, reason: "Daily operations")

    delete session_path

    assert_not_nil authorization.reload.revoked_at
    assert_nil authorization.browser_session_id
  end

  test "returns to the protected page after authentication" do
    get root_path
    assert_redirected_to new_session_path

    post session_path, params: { email_address: @user.email_address, password: "password" }

    assert_redirected_to root_url
  end

  test "sign out clears the selected person context before another user signs in" do
    sign_in_as users(:two)
    patch person_context_path, params: { person_id: people(:without_login).id }
    delete session_path

    post session_path, params: {
      email_address: users(:one).email_address,
      password: "password"
    }
    get root_path

    assert_select "h1", "Today"
    assert_select "p", people(:one).name
    assert_select "p", text: people(:without_login).name, count: 0
  end

  test "new authentication clears selected person context without an explicit sign out" do
    sign_in_as users(:two)
    patch person_context_path, params: { person_id: people(:without_login).id }

    post session_path, params: {
      email_address: users(:one).email_address,
      password: "password"
    }
    get root_path

    assert_select "h1", "Today"
    assert_select "p", people(:one).name
    assert_select "p", text: people(:without_login).name, count: 0
  end
end
