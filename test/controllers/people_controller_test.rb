require "test_helper"

class PeopleControllerTest < ActionDispatch::IntegrationTest
  test "anonymous requests require authentication" do
    get people_path
    assert_redirected_to new_session_path

    get new_person_path
    assert_redirected_to new_session_path

    post people_path, params: { person: { name: "Guest" } }
    assert_redirected_to new_session_path
  end

  test "owner lists every household person" do
    sign_in_as users(:one)

    get people_path

    assert_response :success
    assert_select "section[aria-labelledby='people-heading']" do
      households(:home).people.each do |person|
        assert_select "li", text: /#{person.name}/
      end
    end
  end

  test "owner creates a person without a login" do
    sign_in_as users(:one)

    assert_difference -> { households(:home).people.count }, 1 do
      assert_no_difference "User.count" do
        post people_path, params: { person: { name: "Taylor" } }
      end
    end

    person = households(:home).people.find_by!(name: "Taylor")
    assert_nil person.user
    assert_redirected_to people_path
    assert_response :see_other
  end

  test "invalid create renders the form" do
    sign_in_as users(:one)

    assert_no_difference "Person.count" do
      post people_path, params: { person: { name: "" } }
    end

    assert_response :unprocessable_entity
    assert_select "#person-errors", text: /Your name can't be blank/
  end

  test "owner edits and updates a person without a login" do
    sign_in_as users(:one)
    person = people(:without_login)

    get edit_person_path(person)
    assert_response :success
    assert_select "h1", text: /#{person.name}/

    patch person_path(person), params: { person: { name: "Jordan Updated" } }

    assert_redirected_to people_path
    assert_response :see_other
    assert_equal "Jordan Updated", person.reload.name
    assert_nil person.user
  end

  test "invalid update renders the form" do
    sign_in_as users(:one)
    person = people(:without_login)

    patch person_path(person), params: { person: { name: "" } }

    assert_response :unprocessable_entity
    assert_select "#person-errors", text: /Your name can't be blank/
    assert_equal "Jordan", person.reload.name
  end

  test "unknown person id is not found" do
    sign_in_as users(:one)

    get edit_person_path(0)
    assert_response :not_found

    patch person_path(0), params: { person: { name: "Nope" } }
    assert_response :not_found
  end
end
