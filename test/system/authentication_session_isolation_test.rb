require "application_system_test_case"

class AuthenticationSessionIsolationTest < ApplicationSystemTestCase
  def self.run_order = :alpha

  test "01 activity data follows the signed-in account" do
    travel_to Time.zone.local(2026, 7, 30, 12) do
      sign_in_via_browser users(:one)
      click_link_and_wait_for_path "Activities", activity_week_path
      assert_selector "form[action='#{planned_workout_path(planned_workouts(:planned_balanced))}']", visible: :all
      sign_in_as_person_via_browser people(:two)

      assert_no_selector "form[action='#{planned_workout_path(planned_workouts(:planned_balanced))}']", visible: :all
      assert_selector "form[action='#{planned_workout_path(planned_workouts(:sam_balanced))}']", visible: :all
    end
  end

  test "02 account controls do not expose person switching" do
    travel_to Time.zone.local(2026, 7, 30, 12) do
      sign_in_via_browser users(:one)
      find("button[data-account-menu-trigger]", visible: :visible, match: :first).click

      assert_no_button "Switch to #{people(:two).name}"
      assert_no_text people(:one).name
      assert_no_text people(:two).name
    end
  end
end
