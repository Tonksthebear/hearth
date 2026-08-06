require "test_helper"

class PlannedMealIngredient::ReplacementDecisionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:one)
    @requirement = planned_meal_ingredients(:soup_carrots_substituted)
    @planned_meal = planned_meals(:shared_soup_target_week)
  end

  test "the substituted row offers the replacement's decisions, not the original's" do
    get planned_meal_ingredient_review_path(@planned_meal)

    assert_response :success
    assert_select "#requirement-#{@requirement.id}", text: /Substituted → Blueberries/
    assert_select "form[action=?] input[name='replacement_decision'][value='on_hand']", replacement_path, count: 1
    assert_select "form[action=?] input[name='replacement_decision'][value='missing']", replacement_path, count: 1
    assert_select "form[action=?] input[name='decision'][value='on_hand']", decision_path, count: 0
  end

  test "on hand records the replacement decision and writes evidence for the replacement only" do
    get planned_meal_ingredient_review_path(@planned_meal)

    patch replacement_path, params: { replacement_decision: "on_hand" }

    assert_redirected_to planned_meal_ingredient_review_path(@planned_meal)
    assert_response :see_other
    assert_equal "on_hand", @requirement.reload.replacement_decision
    blueberries = PantryItem.find_by!(household: households(:home), ingredient: ingredients(:blueberries))
    assert_equal [ "confirmed", Rational(1), "cup" ], [ blueberries.state, blueberries.quantity, blueberries.unit ]
    assert_equal 0, PantryItem.where(ingredient: ingredients(:carrots)).count
  end

  test "missing records the replacement decision without pantry evidence" do
    patch replacement_path, params: { replacement_decision: "missing" }

    assert_equal "missing", @requirement.reload.replacement_decision
    assert_equal "low", pantry_items(:low_blueberries).reload.state
  end

  test "a replacement cannot itself be substituted or marked not needed" do
    assert_no_changes -> { @requirement.reload.replacement_decision } do
      patch replacement_path, params: { replacement_decision: "not_needed" }
    end

    assert_response :not_found
  end

  test "a requirement that is not substituted has no replacement decision to make" do
    patch planned_meal_ingredient_replacement_decision_path(planned_meal_ingredients(:shared_salad_lettuce)),
      params: { replacement_decision: "on_hand" }

    assert_response :not_found
  end

  test "a cooked plan's replacement can no longer be decided" do
    @planned_meal.convert_for!(people(:one), today: @planned_meal.planned_on)

    assert_no_changes -> { @requirement.reload.replacement_decision } do
      patch replacement_path, params: { replacement_decision: "on_hand" }
    end

    assert_response :not_found
  end

  private
    def replacement_path
      planned_meal_ingredient_replacement_decision_path(@requirement)
    end

    def decision_path
      planned_meal_ingredient_decision_path(@requirement)
    end
end
