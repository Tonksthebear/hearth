require "application_system_test_case"

class HouseholdPeopleAndPersonContextTest < ApplicationSystemTestCase
  test "owner manages a login-less person and switches persistent context" do
    visit new_session_path
    fill_in "Email address", with: users(:one).email_address
    fill_in "Password", with: "password"
    click_button_and_wait_for_path "Sign in", root_path

    click_link_and_wait_for_path "Manage people", people_path
    assert_selector "section[aria-labelledby='people-heading'] h1", text: "People"
    click_link_and_wait_for_path "Add person", new_person_path
    assert_selector "section[aria-labelledby='new-person-heading'] h1", text: "Add person"
    assert_no_selector "html[aria-busy='true']"
    fill_in_and_wait_for_value "Name", "Taylor"
    assert_field "Name", with: "Taylor"
    click_button_and_wait_for_path "Create Person", people_path

    assert_selector "section[aria-labelledby='people-heading'] li", text: "Taylor"
    person = Person.find_by!(name: "Taylor")
    assert_no_selector "html[aria-busy='true']"
    click_link_and_wait_for_path "Edit", edit_person_path(person), href: edit_person_path(person)
    assert_no_selector "html[aria-busy='true']"
    fill_in_and_wait_for_value "Name", "Taylor Updated"
    assert_field "Name", with: "Taylor Updated"
    click_button_and_wait_for_path "Update Person", people_path

    assert_selector "section[aria-labelledby='people-heading'] li", text: "Taylor Updated"
    assert_nil person.reload.user

    assert_no_selector "html[aria-busy='true']"
    click_button_and_wait_for_path "Switch to Taylor Updated", root_path
    assert_selector "section[aria-labelledby='current-person-heading'] h2", text: "Taylor Updated"
    assert_selector "section[aria-labelledby='household-heading'] h1", text: households(:home).name

    assert_no_selector "html[aria-busy='true']"
    click_link_and_wait_for_path "Manage people", people_path
    assert_selector "section[aria-labelledby='people-heading'] h1", text: "People"
    assert_no_selector "html[aria-busy='true']"
    click_link_and_wait_for_path "Hearth", root_path
    assert_selector "section[aria-labelledby='current-person-heading'] h2", text: "Taylor Updated"
    assert_no_selector "section[aria-labelledby='current-person-heading'] h2", text: people(:one).name

    assert_no_selector "html[aria-busy='true']"
    click_button_and_wait_for_text "Switch to #{people(:one).name}", people(:one).name
    assert_selector "section[aria-labelledby='current-person-heading'] h2", text: people(:one).name
    assert_no_selector "section[aria-labelledby='current-person-heading'] h2", text: "Taylor Updated"
  end

  private
    def click_link_and_wait_for_path(label, path, **options)
      link = find_link(label, **options)
      link.click
      execute_script("arguments[0].click()", link) unless page.has_current_path?(path, wait: 5)
      assert_current_path path
    end

    def click_button_and_wait_for_path(label, path)
      button = find_button(label)
      button.click
      execute_script("arguments[0].click()", button) unless page.has_current_path?(path, wait: 5)
      assert_current_path path
    end

    def click_button_and_wait_for_text(label, text)
      button = find_button(label)
      button.click
      execute_script("arguments[0].click()", button) unless page.has_selector?(
        "section[aria-labelledby='current-person-heading'] h2",
        text: text,
        wait: 5
      )
    end

    def fill_in_and_wait_for_value(label, value)
      field = find_field(label)
      field.set(value)
      unless page.has_field?(label, with: value, wait: 5)
        execute_script(<<~JAVASCRIPT, field, value)
          arguments[0].value = arguments[1];
          arguments[0].dispatchEvent(new Event("input", { bubbles: true }));
          arguments[0].dispatchEvent(new Event("change", { bubbles: true }));
        JAVASCRIPT
      end
    end
end
