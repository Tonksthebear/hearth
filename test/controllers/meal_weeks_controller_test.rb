require "test_helper"

class MealWeeksControllerTest < ActionDispatch::IntegrationTest
  test "renders weekly snapshot totals in the week details disclosure" do
    sign_in_as users(:one)

    get meal_week_path(date: "2026-07-27")

    assert_response :success
    assert_select "el-disclosure#meal-week-details[hidden] #week-nutrition-heading", text: "Nutrition"
    assert_select "el-disclosure#meal-week-details", text: /Protein.*9\.26 g/m
    assert_select "section[aria-labelledby='day-2026-07-27']", text: /Protein/, count: 0
  end

  test "renders the selected person's planned and eaten week" do
    sign_in_as users(:one)

    get meal_week_path, params: { date: "2026-07-27" }

    assert_response :success
    assert_select "h1", text: "Meals"
    assert_select "section[aria-labelledby='day-2026-07-27'] li", text: /#{Regexp.escape(recipes(:salad).title)}/
    assert_select "section[aria-labelledby='day-2026-07-28'] li", text: /#{Regexp.escape(recipes(:alex_only).title)}/
    assert_select "section[aria-labelledby='day-2026-07-28'] li", text: /Dinner with friends/
    assert_select "section[aria-labelledby='day-2026-07-29'] li p",
      text: people(:two).name,
      count: 0
    assert_select "form[action='#{planned_meals_path}']"
    assert_select "a[href^='#{new_meal_path}?date=']", text: "Log meal"
    assert_select "a", text: "Current week"
  end

  test "invalid date inputs safely render the current week" do
    sign_in_as users(:one)

    travel_to Date.new(2026, 7, 27) do
      [ "not-a-date", "2026-02-31" ].each do |date|
        get meal_week_path, params: { date: date }

        assert_response :success
        assert_select "p", text: /July 27, 2026/
        assert_select "section[aria-labelledby='day-2026-07-27']", text: /Monday.*July 27, 2026/m
      end
    end
  end

  test "shopping affordance reads an existing list only and renders only for unchecked items" do
    sign_in_as users(:one)
    list = shopping_lists(:target_week)
    counts = [ ShoppingList.count, ShoppingListItem.count, ShoppingListItemSource.count ]
    timestamps = [ list.updated_at, *list.items.order(:id).pluck(:updated_at) ]

    get meal_week_path, params: { date: list.week_start.iso8601 }

    assert_response :success
    assert_select "[data-shopping-attention]"
    assert_select "a[href=?][data-turbo-prefetch='false']", shopping_list_path(date: list.week_start.iso8601), text: /Open shopping list \(1\)/
    assert_equal counts, [ ShoppingList.count, ShoppingListItem.count, ShoppingListItemSource.count ]
    assert_equal timestamps, [ list.reload.updated_at, *list.items.order(:id).pluck(:updated_at) ]

    list.items.update_all(completed_at: Time.current)
    get meal_week_path, params: { date: list.week_start.iso8601 }
    assert_select "[data-shopping-attention]", count: 0
    assert_select "a", text: /Open shopping list \(/, count: 0

    list.destroy!
    get meal_week_path, params: { date: "2026-07-27" }
    assert_select "[data-shopping-attention]", count: 0
    assert_select "a", text: /Open shopping list \(/, count: 0
    refute ShoppingList.exists?(household: households(:home), week_start: Date.new(2026, 7, 27))
  end

  test "planned cards surface readiness badges without reconciling shopping or writing pantry evidence" do
    sign_in_as users(:one)
    pantry_before = pantry_items(:out_lettuce).attributes
    decisions_before = PlannedMealIngredient.order(:id).pluck(:id, :decision, :decided_at)

    get meal_week_path, params: { date: "2026-07-27" }

    assert_response :success
    assert_select "[data-readiness-state='shopping_needed']", text: /Shopping needed/
    assert_select "[data-readiness-state='needs_ingredient_check']", text: /Needs ingredient check/
    assert_equal pantry_before, pantry_items(:out_lettuce).reload.attributes
    assert_equal decisions_before, PlannedMealIngredient.order(:id).pluck(:id, :decision, :decided_at)
  end
end
