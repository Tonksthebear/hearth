require "test_helper"

class ActivityLibrariesControllerTest < ActionDispatch::IntegrationTest
  test "renders catalog and keeps specialized training and recovery paths reachable" do
    sign_in_as users(:one)

    get activity_library_path

    assert_response :success
    assert_select "h1", "Library"
    assert_select "a[href=?]", training_week_path
    assert_select "a[href=?]", recovery_day_path
    assert_select "section[aria-labelledby='library-recovery-heading'] li",
      text: /#{Regexp.escape(person_habits(:sam_movement).habit.name)}/,
      count: 0
  end
end
