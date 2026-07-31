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
    assert_select "h1", "Today"
    assert_select "p", people(:two).name

    patch person_context_path, params: { person_id: people(:one).id }
    assert_redirected_to root_path

    get root_path
    assert_select "p", people(:one).name
  end

  test "destination keys redirect only to fixed internal routes" do
    sign_in_as users(:one)

    patch person_context_path, params: { person_id: people(:two).id, destination: "meals" }
    assert_redirected_to meal_week_path

    patch person_context_path, params: { person_id: people(:one).id, destination: "activities" }
    assert_redirected_to activity_week_path

    patch person_context_path, params: { person_id: people(:two).id, destination: "https://example.com" }
    assert_redirected_to root_path
  end

  test "unknown numeric selection returns not found without changing context" do
    sign_in_as users(:one)
    patch person_context_path, params: { person_id: people(:two).id }

    patch person_context_path, params: { person_id: 0 }

    assert_response :not_found
    get root_path
    assert_select "p", people(:two).name
  end

  test "garbage selection returns not found without changing context" do
    sign_in_as users(:one)
    patch person_context_path, params: { person_id: people(:two).id }

    patch person_context_path, params: { person_id: "not-an-id" }

    assert_response :not_found
    get root_path
    assert_select "p", people(:two).name
  end

  test "stale selection falls back to the signed in person" do
    sign_in_as users(:one)
    selected = people(:without_login)
    patch person_context_path, params: { person_id: selected.id }
    selected.destroy!

    get root_path

    assert_response :success
    assert_select "h1", "Today"
    assert_select "p", people(:one).name
    assert_select "p", text: selected.name, count: 0
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
