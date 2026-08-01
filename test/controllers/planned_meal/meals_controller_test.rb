require "test_helper"

class PlannedMeal::MealsControllerTest < ActionDispatch::IntegrationTest
  test "converts an eligible plan for Current person and redirects repeat requests to the same meal" do
    travel_to Time.zone.local(2026, 7, 31, 12) do
      sign_in_as users(:one)
      plan = planned_meals(:shared_target_week)

      assert_difference "Meal.count", 1 do
        post planned_meal_meal_path(plan)
      end
      meal = plan.meals.find_by!(person: people(:one))
      assert_equal plan.planned_on, meal.eaten_on
      assert_redirected_to meal_path(meal)

      assert_no_difference "Meal.count" do
        post planned_meal_meal_path(plan)
      end
      assert_redirected_to meal_path(meal)
    end
  end

  test "rejects future and invisible plans" do
    travel_to Time.zone.local(2026, 7, 31, 12) do
      sign_in_as users(:one)

      assert_no_difference "Meal.count" do
        post planned_meal_meal_path(planned_meals(:adjacent_week))
      end
      assert_redirected_to meal_week_path(date: planned_meals(:adjacent_week).planned_on)
      assert_equal "That plan can no longer be logged.", flash[:alert]

      post planned_meal_meal_path(planned_meals(:sam_target_week))
      assert_response :not_found
    end
  end
end
