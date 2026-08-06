require "test_helper"

class PlannedMealsControllerTest < ActionDispatch::IntegrationTest
  test "creates a scoped plan and redirects back to its week" do
    sign_in_as users(:one)

    assert_difference "PlannedMeal.count", 1 do
      post planned_meals_path, params: {
        date: "2026-07-27",
        planned_meal: {
          planned_on: "2026-07-31",
          recipe_id: recipes(:porridge).id,
          person_id: people(:one).id
        }
      }
    end

    planned_meal = PlannedMeal.order(:created_at).last
    assert_equal households(:home), planned_meal.household
    assert_equal people(:one), planned_meal.person
    assert_redirected_to meal_week_path(date: "2026-07-27")
    assert_response :see_other
    assert ShoppingList.exists?(household: households(:home), week_start: Date.new(2026, 7, 27))
    assert ShoppingListItemSource.exists?(planned_meal: planned_meal)

    requirements = planned_meal.planned_meal_ingredients.active.to_a
    assert_equal recipes(:porridge).recipe_ingredients.map(&:id), requirements.map(&:source_recipe_ingredient_id)
    assert_equal [ Rational(1), Rational(1, 2) ], requirements.map(&:quantity)
    assert_equal [ true ], requirements.map(&:untouched?).uniq
    assert_equal 1, planned_meal.recipe_scale
  end

  test "invalid scoped ids render the complete week without creating a shared plan" do
    sign_in_as users(:one)

    assert_no_difference "PlannedMeal.count" do
      post planned_meals_path, params: {
        date: "2026-07-27",
        planned_meal: {
          planned_on: "2026-07-31",
          recipe_id: recipes(:porridge).id,
          person_id: 0
        }
      }
    end

    assert_response :unprocessable_entity
    assert_select "#planned-meal-errors", text: /Person is not available/
    assert_select "h2", text: "Plan a meal"
    assert_select "h2", text: "Log what was eaten"
    assert_select "section", text: /Dinner with friends/
  end

  test "invalid recipe id creates nothing" do
    sign_in_as users(:one)

    assert_no_difference "PlannedMeal.count" do
      post planned_meals_path, params: {
        date: "2026-07-27",
        planned_meal: {
          planned_on: "2026-07-31",
          recipe_id: 0,
          person_id: ""
        }
      }
    end

    assert_response :unprocessable_entity
    assert_select "#planned-meal-errors", text: /Recipe must exist/
    assert_select "#planned-meal-errors li", count: 1
  end

  test "an untouched required recipe renders the validation alert and blank choice" do
    sign_in_as users(:one)

    assert_no_difference "PlannedMeal.count" do
      post planned_meals_path, params: {
        date: "2026-07-27",
        planned_meal: {
          planned_on: "2026-07-31",
          recipe_id: "",
          person_id: ""
        }
      }
    end

    assert_response :unprocessable_entity
    assert_select "#planned-meal-errors", text: /Recipe must exist/
    assert_select "select#planned_meal_recipe_id option[value='']", text: "Choose a recipe"
  end

  test "destroys only a household plan and preserves the week" do
    sign_in_as users(:one)
    planned_meal = planned_meals(:alex_target_week)

    list = ShoppingList.for(household: households(:home), date: planned_meal.planned_on)
    assert_difference "PlannedMeal.count", -1 do
      delete planned_meal_path(planned_meal), params: { date: "2026-07-27" }
    end

    assert_redirected_to meal_week_path(date: "2026-07-27")
    assert_response :see_other
    refute ShoppingListItemSource.exists?(planned_meal_id: planned_meal.id)
    assert list.reload.persisted?
  end

  test "does not destroy a plan that has been logged" do
    sign_in_as users(:one)
    planned_meal = planned_meals(:alex_target_week)
    planned_meal.meals.create!(
      person: people(:one),
      household: households(:home),
      eaten_on: planned_meal.planned_on,
      meal_items_attributes: [ { source_kind: :free_text, snapshot_label: "Logged food", position: 1 } ]
    )

    assert_no_difference "PlannedMeal.count" do
      delete planned_meal_path(planned_meal), params: { date: "2026-07-27" }
    end

    assert_redirected_to meal_week_path(date: "2026-07-27")
    assert_equal "A plan that has been logged cannot be removed.", flash[:alert]
  end
end
