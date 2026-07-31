require "application_system_test_case"

class TodayNavigationTest < ApplicationSystemTestCase
  test "runs the current-person Today path and traverses the new information architecture" do
    travel_to Time.zone.local(2026, 7, 30, 12) do
      person_habits(:alex_water).habit_check_ins.destroy_all
      sign_in_via_browser users(:one)

      assert_selector "h1", text: "Today"
      assert_selector "[data-activity-kind='planned_meal']", text: recipes(:observed_soup).title
      assert_selector "[data-activity-kind='workout']", text: training_sessions(:in_progress).snapshot_title

      within "[data-activity-kind='simple_habit']", text: "Water" do
        click_button "Check off"
      end
      assert_current_path root_path, wait: 5
      assert_selector "[data-activity-kind='habit_check_in']", text: "Water"

      click_link_and_wait_for_path "Meals", meal_week_path
      click_link_and_wait_for_path "Activities", activity_week_path

      click_link_and_wait_for_path people(:one).name, person_path(people(:one)), match: :first
      assert_link "Open #{people(:one).name}'s meals"

      click_link_and_wait_for_path "Hearth", root_path
      click_link_and_wait_for_path "Household overview", household_week_path
      assert_selector "h1", text: "Household week"
    end
  end

  test "keeps plan corrections on Today and starts a due workout from there" do
    travel_to Time.zone.local(2026, 7, 30, 12) do
      sign_in_via_browser users(:one)
      plan = planned_workouts(:planned_balanced)

      within "[data-activity-kind='workout']", text: workout_templates(:balanced).title do
        fill_in "Skip reason (optional)", with: "Not ready"
        click_button "Skip"
      end
      assert_current_path root_path, wait: 5
      assert_selector "[data-activity-status='skipped']", text: "Not ready"

      within "[data-activity-status='skipped']", text: workout_templates(:balanced).title do
        click_button "Restore"
      end
      assert_current_path root_path, wait: 5

      within "[data-activity-kind='workout']", text: workout_templates(:balanced).title do
        click_button "Start"
      end
      assert_text "Workout started.", wait: 5
      assert_current_path edit_training_session_path(plan.reload.training_session), wait: 5
      assert_equal :in_progress, plan.status
    end
  end
end
