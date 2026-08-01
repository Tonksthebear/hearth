require "test_helper"

class TodaysControllerTest < ActionDispatch::IntegrationTest
  test "renders concise same-day nutrition snapshot context" do
    sign_in_as users(:one)
    travel_to Time.zone.local(2026, 7, 27, 12) do
      get root_path

      assert_response :success
      assert_select "#today-nutrition-heading", text: "Known nutrition today"
      assert_select "section", text: /Protein.*9\.26 g/m
      assert_select "p", text: /not medical advice/i
    end
  end

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
      assert_select "[data-activity-kind='planned_meal']", text: /#{Regexp.escape(recipes(:observed_soup).title)}/
      assert_select "[data-activity-kind='workout']", text: /#{Regexp.escape(training_sessions(:in_progress).snapshot_title)}/
      assert_select "[data-activity-kind='simple_habit'] form[action=?]", habit_check_ins_path
      assert_select "a[href=?]", household_week_path, text: "Household overview"
      assert_select "[data-activity-kind='workout']",
        text: /#{Regexp.escape(training_sessions(:other_person).snapshot_title)}/,
        count: 0
    end
  end

  test "root is the sole Today route" do
    assert_raises ActionController::RoutingError do
      Rails.application.routes.recognize_path("/today")
    end
  end

  test "Today reads an existing current list without creating or reconciling" do
    travel_to Time.zone.local(2026, 7, 30, 12) do
      sign_in_as users(:one)
      counts = [ ShoppingList.count, ShoppingListItem.count, ShoppingListItemSource.count ]

      get root_path

      assert_response :success
      assert_select "a[href=?][data-turbo-prefetch='false']", shopping_list_path(date: "2026-07-30"), text: /Shopping list \(1\)/
      assert_equal counts, [ ShoppingList.count, ShoppingListItem.count, ShoppingListItemSource.count ]

      shopping_lists(:target_week).destroy!
      get root_path
      assert_select "a", text: /Shopping list \(/, count: 0
      refute ShoppingList.exists?(household: households(:home), week_start: Date.new(2026, 7, 27))
    end
  end
end
