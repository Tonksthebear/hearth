require "application_system_test_case"

class HouseholdPeopleAndPersonContextTest < ApplicationSystemTestCase
  test "interactive navigation and cancellation colors respond to dark mode" do
    page.driver.browser.execute_cdp(
      "Emulation.setEmulatedMedia",
      features: [ { name: "prefers-color-scheme", value: "light" } ]
    )
    sign_in_via_browser users(:one)

    week_link = find_link("Previous week", visible: :visible)
    week_link_classes = week_link[:class]
    light_week_color = computed_color(week_link)

    page.driver.browser.execute_cdp(
      "Emulation.setEmulatedMedia",
      features: [ { name: "prefers-color-scheme", value: "dark" } ]
    )
    dark_week_color = computed_color(week_link)

    click_link_and_wait_for_path "Manage people", people_path
    click_link_and_wait_for_path "Add person", new_person_path
    cancel_link = find_link("Cancel", visible: :visible)
    dark_cancel_color = computed_color(cancel_link)

    page.driver.browser.execute_cdp(
      "Emulation.setEmulatedMedia",
      features: [ { name: "prefers-color-scheme", value: "light" } ]
    )
    light_cancel_color = computed_color(cancel_link)

    assert_not_equal light_week_color, dark_week_color
    assert_not_equal light_cancel_color, dark_cancel_color
    assert_includes week_link_classes, "dark:text-primary-300"
    assert_includes cancel_link[:class], "dark:text-gray-300"
  ensure
    page.driver.browser.execute_cdp("Emulation.setEmulatedMedia", features: [])
  end

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
    click_element_and_wait_for_path find("a[aria-label='Edit Taylor']"), edit_person_path(person)
    assert_no_selector "html[aria-busy='true']"
    fill_in_and_wait_for_value "Name", "Taylor Updated"
    assert_field "Name", with: "Taylor Updated"
    click_button_and_wait_for_path "Update Person", people_path

    assert_selector "section[aria-labelledby='people-heading'] li", text: "Taylor Updated"
    assert_nil person.reload.user

    assert_no_selector "html[aria-busy='true']"
    switch_person_via_browser person
    assert_selector "article[data-current-person='true'] h3", text: "Taylor Updated"
    assert_selector "[data-household-name]", text: /#{Regexp.escape(households(:home).name)}/i

    assert_no_selector "html[aria-busy='true']"
    click_link_and_wait_for_path "Manage people", people_path
    assert_selector "section[aria-labelledby='people-heading'] h1", text: "People"
    assert_no_selector "html[aria-busy='true']"
    click_link_and_wait_for_path "Hearth", root_path
    assert_selector "article[data-current-person='true'] h3", text: "Taylor Updated"
    assert_no_selector "article[data-current-person='true'] h3", text: people(:one).name

    assert_no_selector "html[aria-busy='true']"
    switch_person_via_browser people(:one)
    assert_selector "article[data-current-person='true'] h3", text: people(:one).name, wait: 5
    assert_no_selector "article[data-current-person='true'] h3", text: "Taylor Updated"
  end

  private
    def computed_color(element)
      page.evaluate_script("getComputedStyle(arguments[0]).color", element)
    end
end
