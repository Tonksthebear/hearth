require "test_helper"

class MealLogsControllerTest < ActionDispatch::IntegrationTest
  test "logs a catalog recipe for Current.person and ignores a forged person id" do
    sign_in_as users(:one)

    assert_difference "MealLog.count", 1 do
      post meal_logs_path, params: {
        date: "2026-07-27",
        meal_log: {
          eaten_on: "2026-07-31",
          recipe_id: recipes(:porridge).id,
          ad_hoc_description: "",
          person_id: people(:two).id
        }
      }
    end

    meal_log = MealLog.order(:created_at).last
    assert_equal people(:one), meal_log.person
    assert_equal recipes(:porridge), meal_log.recipe
    assert_redirected_to meal_week_path(date: "2026-07-27")
    assert_response :see_other
  end

  test "logs an ad hoc meal without changing the catalog" do
    sign_in_as users(:one)

    assert_difference "MealLog.count", 1 do
      assert_no_difference "Recipe.count" do
        post meal_logs_path, params: {
          date: "2026-07-27",
          meal_log: {
            eaten_on: "2026-07-31",
            recipe_id: "",
            ad_hoc_description: "Airport sandwich"
          }
        }
      end
    end

    assert_equal "Airport sandwich", MealLog.order(:created_at).last.ad_hoc_description
    assert_response :see_other
  end

  test "invalid choice renders the complete week with errors" do
    sign_in_as users(:one)

    assert_no_difference "MealLog.count" do
      post meal_logs_path, params: {
        date: "2026-07-27",
        meal_log: {
          eaten_on: "2026-07-31",
          recipe_id: recipes(:porridge).id,
          ad_hoc_description: "Also supplied"
        }
      }
    end

    assert_response :unprocessable_entity
    assert_select "#meal-log-errors", text: /Choose a recipe or describe an ad hoc meal/
    assert_select "h2", text: "Plan a meal"
    assert_select "h2", text: "Log what was eaten"
    assert_select "section", text: /#{Regexp.escape(recipes(:salad).title)}/
  end

  test "invalid scoped recipe id cannot become an ad hoc log" do
    sign_in_as users(:one)

    assert_no_difference "MealLog.count" do
      post meal_logs_path, params: {
        date: "2026-07-27",
        meal_log: {
          eaten_on: "2026-07-31",
          recipe_id: 0,
          ad_hoc_description: "Forged recipe"
        }
      }
    end

    assert_response :unprocessable_entity
    assert_select "#meal-log-errors", text: /Recipe is not available/
  end

  test "cannot destroy another person's meal log" do
    sign_in_as users(:one)

    assert_no_difference "MealLog.count" do
      delete meal_log_path(meal_logs(:sam_recipe_target_week)), params: { date: "2026-07-27" }
    end

    assert_response :not_found
  end
end
