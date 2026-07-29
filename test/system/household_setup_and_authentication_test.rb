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

    assert_selector "section[aria-labelledby='household-heading'] h1", text: "Bear House"
    assert_selector "section[aria-labelledby='current-person-heading'] h2", text: "Tonks"

    click_button "Sign out"
    assert_selector "h1", text: "Sign in"

    fill_in "Email address", with: "tonks@example.com"
    fill_in "Password", with: "secret password"
    click_button "Sign in"

    assert_selector "section[aria-labelledby='household-heading'] h1", text: "Bear House"

    visit new_setup_household_path
    assert_selector "section[aria-labelledby='household-heading'] h1", text: "Bear House"
    assert_no_selector "h1", text: "Create your household"
  end

  private
    def clear_installation
      Session.delete_all
      User.delete_all
      MealLog.delete_all
      PlannedMeal.delete_all
      Person.delete_all
      RecipeInstruction.delete_all
      RecipeIngredient.delete_all
      Recipe.delete_all
      Household.delete_all
    end
end
