require "application_system_test_case"

class HouseholdPeopleAndPersonContextTest < ApplicationSystemTestCase
  test "owner manages a login-less person and switches persistent context" do
    visit new_session_path
    fill_in "Email address", with: users(:one).email_address
    fill_in "Password", with: "password"
    click_button "Sign in"

    assert_link "Manage people"
    visit people_path
    assert_selector "section[aria-labelledby='people-heading'] h1", text: "People"
    assert_link "Add person"
    visit new_person_path
    assert_selector "section[aria-labelledby='new-person-heading'] h1", text: "Add person"
    set_name_field "Taylor"
    assert_field "person_name", with: "Taylor"
    submit_form("Create Person")

    assert_selector "section[aria-labelledby='people-heading'] li", text: "Taylor"
    person = Person.find_by!(name: "Taylor")
    visit edit_person_path(person)
    set_name_field "Taylor Updated"
    submit_form("Update Person")

    assert_selector "section[aria-labelledby='people-heading'] li", text: "Taylor Updated"
    assert_nil person.reload.user

    within "section[aria-labelledby='person-context-heading']" do
      form = find_button("Switch to Taylor Updated").ancestor("form")
      execute_script("arguments[0].requestSubmit()", form)
    end
    assert_current_path root_path
    assert_selector "section[aria-labelledby='current-person-heading'] h2", text: "Taylor Updated"
    assert_selector "section[aria-labelledby='household-heading'] h1", text: households(:home).name

    visit people_path
    assert_selector "section[aria-labelledby='people-heading'] h1", text: "People"
    visit root_path
    assert_selector "section[aria-labelledby='current-person-heading'] h2", text: "Taylor Updated"
    assert_no_selector "section[aria-labelledby='current-person-heading'] h2", text: people(:one).name

    visit people_path
    within "section[aria-labelledby='person-context-heading']" do
      form = find_button("Switch to #{people(:one).name}").ancestor("form")
      execute_script("arguments[0].requestSubmit()", form)
    end
    assert_current_path root_path
    assert_selector "section[aria-labelledby='current-person-heading'] h2", text: people(:one).name
    assert_no_selector "section[aria-labelledby='current-person-heading'] h2", text: "Taylor Updated"
  end

  private
    def submit_form(button_text)
      form = find_button(button_text).ancestor("form")
      execute_script("arguments[0].requestSubmit()", form)
    end

    def set_name_field(value)
      field = find_field("person_name")
      execute_script(<<~JAVASCRIPT, field, value)
        arguments[0].value = arguments[1]
        arguments[0].dispatchEvent(new Event("input", { bubbles: true }))
      JAVASCRIPT
    end
end
