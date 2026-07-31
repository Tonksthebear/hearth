require "application_system_test_case"

class TodayNavigationTest < ApplicationSystemTestCase
  test "runs the current-person Today path and traverses the new information architecture" do
    travel_to Time.zone.local(2026, 7, 30, 12) do
      person_habits(:alex_water).habit_check_ins.destroy_all
      sign_in_via_browser users(:one)

      assert_selector "h1", text: "Today"
      assert_selector "[data-today-kind='planned_meal']", text: recipes(:observed_soup).title
      assert_selector "[data-today-kind='training_session']", text: training_sessions(:draft).snapshot_title

      within "[data-today-kind='simple_habit']", text: "Water" do
        click_button "Check off"
      end
      assert_current_path root_path, wait: 5
      assert_selector "[data-today-kind='habit_check_in']", text: "Water"

      click_link_and_wait_for_path "Meals", meal_week_path
      click_link_and_wait_for_path "Activities", activity_overview_path

      click_link_and_wait_for_path people(:one).name, person_path(people(:one)), match: :first
      assert_link "Open #{people(:one).name}'s meals"

      click_link_and_wait_for_path "Hearth", root_path
      click_link_and_wait_for_path "Household overview", household_week_path
      assert_selector "h1", text: "Household week"
    end
  end
end
