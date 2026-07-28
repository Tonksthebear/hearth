require "application_system_test_case"

class HouseholdPeopleAndPersonContextTest < ApplicationSystemTestCase
  test "owner manages a login-less person and switches persistent context" do
    visit new_session_path
    fill_in "Email address", with: users(:one).email_address
    fill_in "Password", with: "password"
    click_button "Sign in"

    click_link "Manage people"
    assert_selector "section[aria-labelledby='people-heading'] h1", text: "People"
    click_link "Add person"
    assert_selector "section[aria-labelledby='new-person-heading'] h1", text: "Add person"
    fill_in "Name", with: "Taylor"
    click_button "Create Person"

    assert_selector "section[aria-labelledby='people-heading'] li", text: "Taylor"
    person = Person.find_by!(name: "Taylor")
    find("a[aria-label='Edit Taylor']").click
    fill_in "Name", with: "Taylor Updated"
    click_button "Update Person"

    assert_selector "section[aria-labelledby='people-heading'] li", text: "Taylor Updated"
    assert_nil person.reload.user

    click_button "Switch to Taylor Updated"
    assert_current_path root_path
    assert_selector "section[aria-labelledby='current-person-heading'] h2", text: "Taylor Updated"
    assert_selector "section[aria-labelledby='household-heading'] h1", text: households(:home).name

    click_link "Manage people"
    assert_selector "section[aria-labelledby='people-heading'] h1", text: "People"
    click_link "Hearth"
    assert_selector "section[aria-labelledby='current-person-heading'] h2", text: "Taylor Updated"
    assert_no_selector "section[aria-labelledby='current-person-heading'] h2", text: people(:one).name

    click_button "Switch to #{people(:one).name}"
    assert_current_path root_path
    assert_selector "section[aria-labelledby='current-person-heading'] h2", text: people(:one).name
    assert_no_selector "section[aria-labelledby='current-person-heading'] h2", text: "Taylor Updated"
  end
end
