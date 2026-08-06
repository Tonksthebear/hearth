require "test_helper"

class PlannedMeal::OnHandConfirmationsControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:one) }

  test "the fast path answers every undecided requirement and records its evidence" do
    plan = planned_meals(:shared_target_week)
    pantry_items(:out_lettuce).destroy!
    get planned_meal_ingredient_review_path(plan)
    assert_select "form[action=?]", planned_meal_on_hand_confirmation_path(plan)

    post planned_meal_on_hand_confirmation_path(plan)

    assert_redirected_to planned_meal_ingredient_review_path(plan)
    assert_response :see_other
    assert_predicate planned_meal_ingredients(:shared_salad_lettuce).reload, :on_hand?
    lettuce = PantryItem.find_by!(household: households(:home), ingredient: ingredients(:lettuce))
    assert_equal [ "confirmed", Rational(1), "head" ], [ lettuce.state, lettuce.quantity, lettuce.unit ]
    assert_equal people(:one), lettuce.confirmed_by

    follow_redirect!
    assert_select "[data-readiness-state='ready_to_cook']"
  end

  test "the fast path never reverses a decision the household already made" do
    plan = planned_meals(:shared_soup_target_week)
    substituted = planned_meal_ingredients(:soup_carrots_substituted)

    post planned_meal_on_hand_confirmation_path(plan)

    assert_response :not_found
    assert_predicate substituted.reload, :substituted?
    assert_equal "unknown", substituted.replacement_decision
  end

  test "a plan with nothing left to answer offers no fast path and rejects the request" do
    plan = planned_meals(:sam_target_week)

    post planned_meal_on_hand_confirmation_path(plan)

    assert_response :not_found
  end

  test "a cooked plan can no longer be answered in bulk" do
    plan = planned_meals(:shared_target_week)
    plan.convert_for!(people(:one), today: plan.planned_on)

    post planned_meal_on_hand_confirmation_path(plan)

    assert_response :not_found
  end
end
