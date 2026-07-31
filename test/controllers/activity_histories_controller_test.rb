require "test_helper"

class ActivityHistoriesControllerTest < ActionDispatch::IntegrationTest
  test "renders selected person completed and skipped outcomes" do
    sign_in_as users(:one)

    get activity_history_path

    assert_response :success
    assert_select "h1", "History"
    assert_select "[data-history-status='skipped']", text: /#{Regexp.escape(planned_workouts(:skipped_balanced).workout_template.title)}/
    assert_select "li[data-history-status]",
      text: /#{Regexp.escape(training_sessions(:other_person).snapshot_title)}/,
      count: 0
    assert_select "a[href=?]", activity_history_path(before: Date.current - ActivityHistory::WINDOW_DAYS.days), text: "Show earlier"
  end

  test "renders an older bounded window with a route back to recent history" do
    sign_in_as users(:one)

    get activity_history_path(before: "2026-04-30")

    assert_response :success
    assert_select "a[href=?]", activity_history_path, text: "Back to recent"
    assert_select "a[href=?]",
      activity_history_path(before: Date.new(2026, 4, 30) - ActivityHistory::WINDOW_DAYS.days),
      text: "Show earlier"
  end
end
