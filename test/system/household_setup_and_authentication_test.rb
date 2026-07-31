require "application_system_test_case"

class HouseholdSetupAndAuthenticationTest < ApplicationSystemTestCase
  test "owner sets up the installation signs out and signs back in" do
    clear_installation

    visit root_path
    assert_selector "h1", text: "Create your household"

    fill_in "Household name", with: "Bear House"
    fill_in "Your name", with: "Tonks"
    fill_in "Email address", with: "tonks@example.com"
    fill_in "Password", with: "secret password"
    fill_in "Confirm password", with: "secret password"
    click_button "Create household"

    assert_selector "[data-household-name]", text: /Bear House/i
    assert_selector "h1", text: "Today"
    assert_text "Tonks"

    find_button("Open person menu").click
    accept_confirm("Sign out of Hearth?") { click_button "Sign out" }
    assert_selector "h1", text: "Sign in"

    fill_in "Email address", with: "tonks@example.com"
    fill_in "Password", with: "secret password"
    click_button "Sign in"

    assert_selector "[data-household-name]", text: /Bear House/i

    visit new_setup_household_path
    assert_selector "[data-household-name]", text: /Bear House/i
    assert_no_selector "h1", text: "Create your household"
  end
end
