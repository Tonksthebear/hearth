require "test_helper"

# Marking a requirement "on hand" is itself a pantry confirmation, so this covers
# one branch per way the quantity rule could fabricate or destroy household stock.
class PlannedMealIngredientOnHandTest < ActiveSupport::TestCase
  CONFIRMED_AT = Time.utc(2026, 7, 31, 9, 30)

  test "an untracked ingredient gains confirmed evidence at the required amount" do
    requirement = planned_meal_ingredients(:shared_salad_lettuce)
    pantry_items(:out_lettuce).destroy!

    travel_to(CONFIRMED_AT) { requirement.answer!(:on_hand, by: people(:one)) }

    assert_predicate requirement.reload, :on_hand?
    assert_equal CONFIRMED_AT, requirement.decided_at
    assert_equal [ "confirmed", Rational(1), "head" ], evidence(:lettuce)
    assert_equal [ PantryItem::READINESS_REVIEW_SOURCE, people(:one), CONFIRMED_AT ], provenance(:lettuce)
  end

  test "an out row is re-established at the required amount" do
    travel_to(CONFIRMED_AT) { planned_meal_ingredients(:shared_salad_lettuce).answer!(:on_hand, by: people(:one)) }

    assert_equal [ "confirmed", Rational(1), "head" ], evidence(:lettuce)
  end

  test "evidence already covering the requirement keeps its exact quantity and refreshes provenance" do
    requirement = planned_meal_ingredients(:shared_salad_lettuce)
    requirement.update!(ingredient: ingredients(:rolled_oats), display_name: "Rolled oats", unit: "cup")

    travel_to(CONFIRMED_AT) { requirement.answer!(:on_hand, by: people(:one)) }

    # The fixture already asserts four cups; one cup is required, and adding to it
    # would invent stock the household never claimed.
    assert_equal [ "confirmed", Rational(4), "cup" ], evidence(:rolled_oats)
    assert_equal [ PantryItem::READINESS_REVIEW_SOURCE, people(:one), CONFIRMED_AT ], provenance(:rolled_oats)
  end

  test "the scaled requirement is confirmed rather than the recipe's authored amount" do
    plan = planned_meals(:shared_target_week)
    plan.update!(recipe_scale: 3)
    pantry_items(:out_lettuce).destroy!

    plan.planned_meal_ingredients.active.sole.answer!(:on_hand, by: people(:one))

    assert_equal [ "confirmed", Rational(3), "head" ], evidence(:lettuce)
  end

  test "an unmeasurable requirement records the decision and writes no evidence" do
    requirement = free_text_requirement

    requirement.answer!(:on_hand, by: people(:one))

    assert_predicate requirement.reload, :on_hand?
    assert_equal 0, PantryItem.where(ingredient: ingredients(:carrots)).count
  end

  test "a confirmed row in an incompatible family is preserved and the decision is still recorded" do
    requirement = planned_meal_ingredients(:shared_salad_lettuce)
    pantry_items(:out_lettuce).confirm!(
      quantity: 2, unit: "cup", source: "pantry_check", confirmed_by: people(:without_login)
    )
    snapshot = observation_snapshot(:lettuce)

    requirement.answer!(:on_hand, by: people(:one))

    assert_predicate requirement.reload, :on_hand?
    assert_equal snapshot, observation_snapshot(:lettuce)
  end

  test "changing the decision away from on hand never retracts the evidence" do
    requirement = planned_meal_ingredients(:shared_salad_lettuce)
    pantry_items(:out_lettuce).destroy!
    requirement.answer!(:on_hand, by: people(:one))

    requirement.decide!(:missing)

    assert_equal [ "confirmed", Rational(1), "head" ], evidence(:lettuce)
  end

  test "a second confirmation converges instead of compounding" do
    requirement = planned_meal_ingredients(:shared_salad_lettuce)
    pantry_items(:out_lettuce).destroy!

    2.times { requirement.answer!(:on_hand, by: people(:one)) }

    assert_equal [ "confirmed", Rational(1), "head" ], evidence(:lettuce)
  end

  test "the replacement path writes evidence for the replacement only" do
    requirement = planned_meal_ingredients(:soup_carrots_substituted)

    travel_to(CONFIRMED_AT) { requirement.answer_replacement!(:on_hand, by: people(:one)) }

    assert_predicate requirement.reload, :substituted?
    assert_equal "on_hand", requirement.replacement_decision
    assert_equal [ "confirmed", Rational(1), "cup" ], evidence(:blueberries)
    assert_equal 0, PantryItem.where(ingredient: ingredients(:carrots)).count
  end

  test "confirming on hand for one plan changes readiness for a different queued plan" do
    pantry_items(:out_lettuce).destroy!
    sam = planned_meals(:sam_target_week)
    assert_predicate allocation.readiness_for(sam), :shopping_needed?

    planned_meal_ingredients(:shared_salad_lettuce).answer!(:on_hand, by: people(:one))

    # Household evidence is shared, so answering the earlier shared plan hands it
    # the stock and Sam's later plan still goes short — the deficit moved rather
    # than disappearing, which is exactly the household-wide effect to prove.
    assert_equal Rational(1), allocation.reserved_for(ingredients(:lettuce))
    assert_predicate allocation.readiness_for(planned_meals(:shared_target_week)), :ready_to_cook?
    assert_predicate allocation.readiness_for(sam), :shopping_needed?
  end

  # The lifecycle guard the controllers used to own. Asking whether the review is
  # open and then writing outside a serialization boundary is check-then-act:
  # cooking commits in the gap, and the write lands anyway. The failure is worse
  # for "on hand" than a stale decision, because it confirms pantry evidence for
  # stock the plan has already drawn.
  test "a requirement cooked between the eligibility check and the write is refused" do
    plan = planned_meals(:shared_target_week)
    requirement = planned_meal_ingredients(:shared_salad_lettuce)
    # Exactly what a controller before_action would have observed.
    assert_predicate requirement.planned_meal, :ingredient_review_open?
    # Cooking commits through another instance while that answer is still true.
    PlannedMeal.find(plan.id).convert_for!(people(:one), today: plan.planned_on)

    assert_raises(ActiveRecord::RecordNotFound) { requirement.answer!(:on_hand, by: people(:one)) }

    assert_predicate requirement.reload, :unknown?
    assert_nil requirement.decided_at
    assert_equal "out", pantry_items(:out_lettuce).reload.state
    assert_nil pantry_items(:out_lettuce).quantity
  end

  test "every review command is refused once the plan has been cooked" do
    plan = planned_meals(:shared_soup_target_week)
    substituted = planned_meal_ingredients(:soup_carrots_substituted)
    plan.convert_for!(people(:one), today: plan.planned_on)

    assert_raises(ActiveRecord::RecordNotFound) { substituted.answer!(:missing, by: people(:one)) }
    assert_raises(ActiveRecord::RecordNotFound) { substituted.answer_replacement!(:on_hand, by: people(:one)) }
    assert_raises(ActiveRecord::RecordNotFound) do
      substituted.substitute!(ingredient: ingredients(:rolled_oats), display_quantity: "1", unit: "cup")
    end
    assert_raises(ActiveRecord::RecordNotFound) { plan.mark_remaining_ingredients_on_hand!(by: people(:one)) }

    substituted.reload
    assert_predicate substituted, :substituted?
    assert_equal [ ingredients(:blueberries), "unknown" ], [ substituted.replacement_ingredient, substituted.replacement_decision ]
    assert_equal "low", pantry_items(:low_blueberries).reload.state
  end

  test "an answer that beats cooking is kept and cooking still draws what it reserved" do
    plan = planned_meals(:shared_target_week)
    requirement = planned_meal_ingredients(:shared_salad_lettuce)
    pantry_items(:out_lettuce).destroy!

    requirement.answer!(:on_hand, by: people(:one))
    plan.convert_for!(people(:one), today: plan.planned_on)

    assert_predicate requirement.reload, :on_hand?
    lettuce = PantryItem.find_by!(household: households(:home), ingredient: ingredients(:lettuce))
    # Confirmed at one head by the answer, then drawn back to zero by cooking.
    assert_equal [ "out", nil ], [ lettuce.state, lettuce.quantity ]
    assert_equal [ Rational(1) ], PantryConsumption.where(planned_meal_id: plan.id).map(&:quantity)
  end

  test "the replacement decision is only resolvable while the row is an active substitution" do
    assert_predicate planned_meal_ingredients(:soup_carrots_substituted), :replacement_resolvable?
    assert_not_predicate planned_meal_ingredients(:shared_salad_lettuce), :replacement_resolvable?
    assert_not_predicate planned_meal_ingredients(:adjacent_free_text_history), :replacement_resolvable?
  end

  private
    def allocation
      Household::PantryAllocation.new(households(:home))
    end

    def free_text_requirement
      planned_meal_ingredients(:soup_carrots_substituted).tap do |requirement|
        requirement.update!(decision: :unknown, **blank_replacement)
        recipe_ingredients(:soup_carrots).update!(display_quantity: "to taste", quantity_numerator: nil, quantity_denominator: nil)
        requirement.update!(display_quantity: "to taste", quantity_numerator: nil, quantity_denominator: nil)
      end
    end

    def blank_replacement
      {
        replacement_ingredient: nil, replacement_display_name: nil, replacement_display_quantity: nil,
        replacement_unit: nil, replacement_quantity_numerator: nil, replacement_quantity_denominator: nil,
        replacement_decision: nil
      }
    end

    def pantry_row(name)
      PantryItem.find_by!(household: households(:home), ingredient: ingredients(name))
    end

    def evidence(name)
      row = pantry_row(name)
      [ row.state, row.quantity, row.unit ]
    end

    def provenance(name)
      row = pantry_row(name)
      [ row.confirmation_source, row.confirmed_by, row.confirmed_at ]
    end

    def observation_snapshot(name)
      pantry_row(name).slice(:state, :quantity_numerator, :quantity_denominator, :unit, :confirmation_source, :confirmed_by_id, :confirmed_at)
    end
end
