require "test_helper"

class ActivityOverviewsControllerTest < ActionDispatch::IntegrationTest
  test "renders current-person activity and all catalog destinations" do
    travel_to Time.zone.local(2026, 7, 30, 12) do
      sign_in_as users(:one)

      get activity_overview_path

      assert_response :success
      assert_select "h1", "Activities"
      assert_select "[data-activity-section]", count: 4
      assert_select "[data-activity-section='training']", text: /#{Regexp.escape(training_sessions(:draft).snapshot_title)}/
      assert_select "body", text: training_sessions(:other_person).snapshot_title, count: 0
      [ training_week_path, recovery_day_path, workout_templates_path, exercises_path ].each do |path|
        assert_select "a[href=?]", path
      end
    end
  end
end
