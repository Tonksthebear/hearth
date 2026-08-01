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
      assert_select "#today-summary-heading", text: "Today at a glance"
      assert_select "[data-today-summary-fact]", count: 3
      assert_select "[data-today-summary-fact='meals']", text: /1 eaten/
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
      other_plan = people(:two).planned_meals.create!(
        household: households(:home),
        recipe: recipes(:salad),
        planned_on: Date.current
      )
      other_meal = people(:two).meals.create!(
        household: households(:home),
        eaten_on: Date.current,
        meal_items_attributes: [ { source_kind: :free_text, snapshot_label: "Sam private meal" } ]
      )
      other_session = people(:two).training_sessions.create!(
        household: households(:home),
        snapshot_title: "Sam private workout",
        performed_on: Date.current,
        started_at: Time.current
      )
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
        text: /#{Regexp.escape(other_session.snapshot_title)}/,
        count: 0
      assert_select "[data-activity-kind='planned_meal']", text: /#{Regexp.escape(other_plan.recipe.title)}/, count: 0
      assert_select "[data-activity-kind='meal']", text: /#{Regexp.escape(other_meal.description)}/, count: 0
      assert_select "[data-activity-kind]", text: /#{Regexp.escape(habits(:movement).name)}/, count: 0

      patch person_context_path, params: { person_id: people(:two).id }
      get root_path
      assert_select "[data-activity-kind='planned_meal']", text: /#{Regexp.escape(other_plan.recipe.title)}/
      assert_select "[data-activity-kind='meal']", text: /#{Regexp.escape(other_meal.description)}/
      assert_select "[data-activity-kind]", text: /#{Regexp.escape(habits(:movement).name)}/
    end
  end

  test "empty selected-person day renders a neutral summary state" do
    sign_in_as users(:one)
    patch person_context_path, params: { person_id: people(:without_login).id }

    travel_to Time.zone.local(2026, 8, 2, 12) do
      get root_path

      assert_response :success
      assert_select "#today-summary-heading"
      assert_select "h3", text: "No plans or logs yet"
      assert_select "[data-today-summary-fact='attention']", count: 0
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
