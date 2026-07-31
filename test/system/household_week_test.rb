require "application_system_test_case"

class HouseholdWeekTest < ApplicationSystemTestCase
  WEEK_START = Date.new(2026, 7, 27)

  test "runs the household week daily loop and reaches primary actions" do
    travel_to Time.zone.local(2026, 7, 27, 12) do
      prepare_household_week_habits
      sign_in_via_browser users(:one)
      assert_selector "h1", text: "Today"
      visit_and_wait_for_path household_week_path

      assert_selector "h1", text: "Household week"
      assert_text "Dinner with friends"
      assert_text "Sam workout"
      assert_text "Post-meal movement"
      assert_text "Informational tracking only"

      click_link_and_wait_for_path "Next week", household_week_path(date: "2026-08-03")
      assert_text "Following week"
      assert_no_text "Sunday balanced day"
      click_link_and_wait_for_path "Previous week", household_week_path(date: "2026-07-27")
      assert_text "Sunday balanced day"
      assert_no_text "Following week"

      click_link_and_wait_for_path "Log a meal", meal_week_path(date: "2026-07-27")
      select_and_wait "No catalog recipe", from: "Recipe eaten"
      fill_in_and_wait_for_value "Ad hoc meal", "Week-view lunch"
      click_button_and_wait_for_text "Log meal", "Week-view lunch was logged for #{people(:one).name}."
      click_link_and_wait_for_path "Hearth", root_path
      assert_text "Week-view lunch"
      visit_and_wait_for_path household_week_path

      click_link_and_wait_for_path "Open shopping list", shopping_list_path(date: "2026-07-27")
      visit_and_wait_for_path household_week_path
      click_link_and_wait_for_path "Log a workout", new_training_session_path(date: "2026-07-27")
      assert_field "Workout date", with: "2026-07-27"
      visit_and_wait_for_path household_week_path
      click_link_and_wait_for_path "Check in on habits", recovery_day_path
      assert_selector "h1", text: "Recovery"
    end
  end

  test "keeps the operating view discoverable at 390 pixels" do
    page.driver.browser.execute_cdp(
      "Emulation.setDeviceMetricsOverride",
      width: 390,
      height: 900,
      deviceScaleFactor: 1,
      mobile: false
    )

    travel_to Time.zone.local(2026, 7, 27, 12) do
      prepare_household_week_habits
      sign_in_via_browser users(:one)
      visit_and_wait_for_path household_week_path

      assert_equal 390, page.evaluate_script("window.innerWidth")
      assert_selector "h1", text: "Household week"
      assert_text people(:one).name
      assert_text people(:two).name
      assert_text people(:without_login).name
      assert_link "Log a meal"
      assert_link "Log a workout"
      assert_link "Check in on habits"
      assert_text "No meals logged this week."
      assert_selector "p", text: "No meals logged this week.", count: 1
      assert_text "Informational tracking only"
    end
  ensure
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end
end
