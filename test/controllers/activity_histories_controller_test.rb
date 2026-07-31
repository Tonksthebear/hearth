require "test_helper"

class ActivityHistoriesControllerTest < ActionDispatch::IntegrationTest
  test "renders selected person completed and skipped outcomes" do
    sign_in_as users(:one)

    get activity_history_path

    assert_response :success
    assert_select "h1", "History"
    assert_select "[data-history-status='skipped']", text: /#{Regexp.escape(planned_workouts(:skipped_balanced).workout_template.title)}/
    assert_select "body", text: training_sessions(:other_person).snapshot_title, count: 0
  end
end
