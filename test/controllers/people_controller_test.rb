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

  test "owner renders a same-household person overview and context-aware destinations" do
    sign_in_as users(:one)

    get person_path(people(:two))

    assert_response :success
    assert_select "h1", people(:two).name
    assert_select "a", text: /Open #{Regexp.escape(people(:two).name)}'s/, count: 0
    assert_select "form", text: /Open #{Regexp.escape(people(:two).name)}'s/, count: 0

    get person_path(people(:one))
    assert_select "a[href=?]", meal_week_path, text: /meals/
    assert_select "a[href=?]", activity_week_path, text: /activities/
  end

  test "household management cannot change or replace an existing login" do
    sign_in_as users(:one)
    person = people(:two)
    user = person.user
    original_email = user.email_address
    original_password_digest = user.password_digest

    patch person_path(person), params: {
      person: {
        name: person.name,
        user_attributes: {
          id: user.id,
          email_address: "taken-over@example.com",
          password: "hijacked-password",
          password_confirmation: "hijacked-password"
        }
      }
    }

    assert_redirected_to people_path
    assert_equal original_email, user.reload.email_address
    assert_equal original_password_digest, user.password_digest
    assert_equal user, person.reload.user

    get edit_person_path(person)
    assert_select "input[name='person[user_attributes][email_address]']", count: 0
    assert_select "p", text: /Existing login details cannot be changed/
  end

  test "person overview outside the sole household scope is not found" do
    sign_in_as users(:one)

    get person_path(0)

    assert_response :not_found
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

  test "owner creates a person with their own login" do
    sign_in_as users(:one)

    assert_difference [ "Person.count", "User.count" ], 1 do
      post people_path, params: {
        person: {
          name: "Taylor",
          user_attributes: {
            email_address: "taylor@example.com",
            password: "password",
            password_confirmation: "password"
          }
        }
      }
    end

    person = households(:home).people.find_by!(name: "Taylor")
    assert_equal "taylor@example.com", person.user.email_address
    assert person.user.authenticate("password")
    assert_redirected_to people_path
  end

  test "invalid login details render with the person form" do
    sign_in_as users(:one)

    assert_no_difference [ "Person.count", "User.count" ] do
      post people_path, params: {
        person: {
          name: "Taylor",
          user_attributes: {
            email_address: users(:one).email_address,
            password: "password",
            password_confirmation: "password"
          }
        }
      }
    end

    assert_response :unprocessable_entity
    assert_select "#person-errors", text: /email address has already been taken/i
  end

  test "invalid create renders the form" do
    sign_in_as users(:one)

    assert_no_difference "Person.count" do
      post people_path, params: { person: { name: "" } }
    end

    assert_response :unprocessable_entity
    assert_select "#person-errors", text: /Your name can't be blank/
    assert_select "input[name='person[user_attributes][email_address]']", count: 1
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

  test "owner adds a login to an existing person" do
    sign_in_as users(:one)
    person = people(:without_login)

    patch person_path(person), params: {
      person: {
        name: person.name,
        user_attributes: {
          email_address: "jordan@example.com",
          password: "password",
          password_confirmation: "password"
        }
      }
    }

    assert_redirected_to people_path
    assert_equal "jordan@example.com", person.reload.user.email_address
    assert person.user.authenticate("password")
  end

  test "invalid update renders the form" do
    sign_in_as users(:one)
    person = people(:without_login)

    patch person_path(person), params: { person: { name: "" } }

    assert_response :unprocessable_entity
    assert_select "#person-errors", text: /Your name can't be blank/
    assert_select "input[name='person[user_attributes][email_address]']", count: 1
    assert_equal "Jordan", person.reload.name
  end

  test "unknown person id is not found" do
    sign_in_as users(:one)

    get edit_person_path(0)
    assert_response :not_found

    get person_path(0)
    assert_response :not_found

    patch person_path(0), params: { person: { name: "Nope" } }
    assert_response :not_found
  end
end
