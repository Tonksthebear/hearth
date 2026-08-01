require "application_system_test_case"

class AuthenticationSessionIsolationTest < ApplicationSystemTestCase
  def self.run_order = :alpha

  test "01 selected person persists within the authenticated browser session" do
    travel_to Time.zone.local(2026, 7, 30, 12) do
      sign_in_via_browser users(:one)
      click_link_and_wait_for_path "Activities", activity_week_path
      assert_selector "form[action='#{planned_workout_path(planned_workouts(:planned_balanced))}']"
      switch_person_via_browser people(:two)

      assert_selector "button", text: people(:two).name
      assert_no_selector "form[action='#{planned_workout_path(planned_workouts(:planned_balanced))}']"
      assert_selector "form[action='#{planned_workout_path(planned_workouts(:sam_balanced))}']"
    end
  end

  test "02 fresh authentication starts from the signing-in user's person" do
    travel_to Time.zone.local(2026, 7, 30, 12) do
      planned_workouts(:planned_balanced).destroy!
      sign_in_via_browser users(:one)
      click_link_and_wait_for_path "Activities", activity_week_path

      assert_selector "button", text: people(:one).name
      assert_no_selector "button", text: people(:two).name
    end
  end
end
