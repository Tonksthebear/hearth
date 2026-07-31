require "test_helper"

class ActivityWeeksControllerTest < ActionDispatch::IntegrationTest
  test "renders requested week with prepared schedule form and current person only" do
    travel_to Time.zone.local(2026, 7, 30, 12) do
      sign_in_as users(:one)

      get activity_week_path(date: "2026-07-30")

      assert_response :success
      assert_select "h1", "Week agenda"
      assert_select "[data-activity-date='2026-07-30']"
      assert_select "form[action=?]", planned_workouts_path
      assert_select "form[action=?]", planned_workout_path(planned_workouts(:sam_balanced)), count: 0
    end
  end

  test "malformed date falls back to the current week" do
    travel_to Time.zone.local(2026, 7, 30, 12) do
      sign_in_as users(:one)

      get activity_week_path(date: "bad")

      assert_response :success
      assert_select "[data-activity-date='2026-07-27']"
    end
  end
end
