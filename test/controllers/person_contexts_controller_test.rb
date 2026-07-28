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
    assert_select "section[aria-labelledby='current-person-heading'] h2", people(:two).name

    patch person_context_path, params: { person_id: people(:one).id }
    assert_redirected_to root_path

    get root_path
    assert_select "section[aria-labelledby='current-person-heading'] h2", people(:one).name
  end

  test "unknown numeric selection returns not found without changing context" do
    sign_in_as users(:one)
    patch person_context_path, params: { person_id: people(:two).id }

    patch person_context_path, params: { person_id: 0 }

    assert_response :not_found
    get root_path
    assert_select "section[aria-labelledby='current-person-heading'] h2", people(:two).name
  end

  test "garbage selection returns not found without changing context" do
    sign_in_as users(:one)
    patch person_context_path, params: { person_id: people(:two).id }

    patch person_context_path, params: { person_id: "not-an-id" }

    assert_response :not_found
    get root_path
    assert_select "section[aria-labelledby='current-person-heading'] h2", people(:two).name
  end

  test "stale selection falls back to the signed in person" do
    sign_in_as users(:one)
    selected = people(:without_login)
    patch person_context_path, params: { person_id: selected.id }
    selected.destroy!

    get root_path

    assert_response :success
    assert_select "section[aria-labelledby='current-person-heading']" do
      assert_select "h2", people(:one).name
      assert_select "h2", text: selected.name, count: 0
    end
  end
end
