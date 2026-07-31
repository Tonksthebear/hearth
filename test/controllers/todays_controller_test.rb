require "test_helper"

class TodaysControllerTest < ActionDispatch::IntegrationTest
  test "fresh anonymous root redirects to setup" do
    clear_installation

    get root_path

    assert_redirected_to new_setup_household_path
  end

  test "configured anonymous root redirects to sign in" do
    get root_path

    assert_redirected_to new_session_path
  end

  test "authenticated root renders selected-person actions rather than household week" do
    travel_to Time.zone.local(2026, 7, 30, 12) do
      person_habits(:alex_water).habit_check_ins.destroy_all
      sign_in_as users(:one)

      get root_path

      assert_response :success
      assert_select "h1", "Today"
      assert_select "h1", text: "Household week", count: 0
      assert_select "[data-today-kind='planned_meal']", text: /#{Regexp.escape(recipes(:observed_soup).title)}/
      assert_select "[data-today-kind='workout']", text: /#{Regexp.escape(training_sessions(:in_progress).snapshot_title)}/
      assert_select "[data-today-kind='simple_habit'] form[action=?]", habit_check_ins_path
      assert_select "a[href=?]", household_week_path, text: "Household overview"
      assert_select "body", text: training_sessions(:other_person).snapshot_title, count: 0
    end
  end

  test "root is the sole Today route" do
    assert_raises ActionController::RoutingError do
      Rails.application.routes.recognize_path("/today")
    end
  end
end
