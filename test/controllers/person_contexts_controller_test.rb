require "test_helper"

class PersonContextsControllerTest < ActionDispatch::IntegrationTest
  test "anonymous update requires authentication" do
    patch person_context_path, params: { person_id: people(:two).id }

    assert_redirected_to new_session_path
  end

  test "owner switches person context" do
    sign_in_as users(:one)

    patch person_context_path, params: { person_id: people(:two).id }

    assert_redirected_to root_path
    assert_response :see_other

    get root_path
    assert_select "article[data-current-person='true'] h3", people(:two).name

    patch person_context_path, params: { person_id: people(:one).id }
    assert_redirected_to root_path

    get root_path
    assert_select "article[data-current-person='true'] h3", people(:one).name
  end

  test "switching selected person neither revokes nor widens an issued grant" do
    sign_in_as users(:one)
    Current.household = households(:home)
    Current.person = people(:one)
    conversation = Agent::Conversation.create!(
      household: Current.household,
      person: Current.person,
      profile: agent_profiles(:hearth),
      title: "Person switch conversation"
    )
    agent_session = Agent::Session.create!(
      household: Current.household,
      person: Current.person,
      conversation: conversation,
      installation: agent_installations(:local),
      browser_session: Current.session,
      external_session_id: "person-switch-session"
    )
    credential = Agent::Grant.issue!(
      conversation: conversation,
      agent_session: agent_session,
      capability_groups: [ "health_read" ],
      expires_at: 10.minutes.from_now
    )

    patch person_context_path, params: { person_id: people(:two).id }

    assert_nil credential.grant.reload.revoked_at
    assert Agent::Grant.verify(
      bearer: credential.bearer,
      browser_session: credential.grant.browser_session,
      conversation: conversation,
      agent_session: agent_session,
      capability: "health.read"
    )

    other_conversation = Agent::Conversation.create!(
      household: households(:home),
      person: people(:two),
      profile: agent_profiles(:hearth),
      title: "Other person"
    )
    assert_nil Agent::Grant.verify(
      bearer: credential.bearer,
      browser_session: credential.grant.browser_session,
      conversation: other_conversation,
      agent_session: agent_session,
      capability: "health.read"
    )
  end

  test "unknown numeric selection returns not found without changing context" do
    sign_in_as users(:one)
    patch person_context_path, params: { person_id: people(:two).id }

    patch person_context_path, params: { person_id: 0 }

    assert_response :not_found
    get root_path
    assert_select "article[data-current-person='true'] h3", people(:two).name
  end

  test "garbage selection returns not found without changing context" do
    sign_in_as users(:one)
    patch person_context_path, params: { person_id: people(:two).id }

    patch person_context_path, params: { person_id: "not-an-id" }

    assert_response :not_found
    get root_path
    assert_select "article[data-current-person='true'] h3", people(:two).name
  end

  test "stale selection falls back to the signed in person" do
    sign_in_as users(:one)
    selected = people(:without_login)
    patch person_context_path, params: { person_id: selected.id }
    selected.destroy!

    get root_path

    assert_response :success
    assert_select "article[data-current-person='true']" do
      assert_select "h3", people(:one).name
      assert_select "h3", text: selected.name, count: 0
    end
  end

  test "person switcher marks the selected context on every authenticated person page" do
    sign_in_as users(:one)
    selected = people(:two)
    patch person_context_path, params: { person_id: selected.id }

    [
      -> { get root_path },
      -> { get people_path },
      -> { get new_person_path },
      -> { get edit_person_path(people(:without_login)) },
      -> { post people_path, params: { person: { name: "" } } },
      -> { patch person_path(people(:without_login)), params: { person: { name: "" } } }
    ].each do |request|
      request.call

      assert_select "section[aria-labelledby='person-context-heading'] [aria-current]", selected.name
      assert_select "section[aria-labelledby='person-context-heading'] button",
        text: /Switch to #{selected.name}/, count: 0
    end
  end
end
