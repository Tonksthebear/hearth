require "test_helper"

class PlannedMealIngredientTest < ActiveSupport::TestCase
  DECIDED_AT = Time.utc(2026, 7, 30, 15, 45)

  test "decisions record their exact time and clear any replacement" do
    requirement = planned_meal_ingredients(:soup_carrots_substituted)

    travel_to DECIDED_AT do
      requirement.decide!(:on_hand)
    end

    assert_predicate requirement.reload, :on_hand?
    assert_equal DECIDED_AT, requirement.decided_at
    assert_nil requirement.replacement_ingredient
    assert_nil requirement.replacement_display_name
    assert_nil requirement.replacement_quantity
    assert_nil requirement.replacement_decision
    assert_predicate requirement, :resolved?
  end

  test "resetting a decision returns the requirement to unknown without forgetting it was touched" do
    requirement = planned_meal_ingredients(:sam_salad_lettuce)

    travel_to DECIDED_AT do
      requirement.reset_decision!
    end

    assert_predicate requirement.reload, :unknown?
    assert_equal DECIDED_AT, requirement.decided_at
    assert_not_predicate requirement, :untouched?
  end

  test "a substitution snapshots the replacement on the plan and never touches the recipe" do
    requirement = planned_meal_ingredients(:shared_salad_lettuce)
    recipe_ingredient = recipe_ingredients(:salad_lettuce)

    travel_to DECIDED_AT do
      requirement.substitute!(ingredient: ingredients(:blueberries), display_quantity: "1 1/2", unit: "cups")
    end

    requirement.reload
    assert_predicate requirement, :substituted?
    assert_equal DECIDED_AT, requirement.decided_at
    assert_equal ingredients(:blueberries), requirement.replacement_ingredient
    assert_equal "Blueberries", requirement.replacement_display_name
    assert_equal Rational(3, 2), requirement.replacement_quantity
    assert_predicate requirement, :replacement_unknown?
    assert_equal recipe_ingredient.attributes, recipe_ingredient.reload.attributes
  end

  test "a replacement resolves only to on hand or missing and never chains another substitution" do
    requirement = planned_meal_ingredients(:soup_carrots_substituted)

    travel_to DECIDED_AT do
      requirement.decide_replacement!(:missing)
    end

    assert_predicate requirement.reload, :replacement_missing?
    assert_equal DECIDED_AT, requirement.decided_at

    assert_raises(ActiveRecord::RecordInvalid) { requirement.decide_replacement!(:substituted) }
    assert_raises(ActiveRecord::RecordInvalid) { requirement.decide_replacement!(:not_needed) }
    assert_predicate requirement.reload, :replacement_missing?
  end

  test "the database rejects a replacement decision outside the resolvable subset" do
    requirement = planned_meal_ingredients(:soup_carrots_substituted)

    assert_raises(ActiveRecord::StatementInvalid) do
      PlannedMealIngredient.connection.execute(
        "UPDATE planned_meal_ingredients SET replacement_decision = 'substituted' WHERE id = #{requirement.id}"
      )
    end
    assert_raises(ActiveRecord::StatementInvalid) do
      PlannedMealIngredient.connection.execute(
        "UPDATE planned_meal_ingredients SET decision = 'stocked' WHERE id = #{requirement.id}"
      )
    end
  end

  test "a replacement only belongs to a substituted requirement and stays in the household" do
    requirement = planned_meal_ingredients(:shared_salad_lettuce)
    requirement.replacement_ingredient = ingredients(:carrots)

    assert_not requirement.valid?
    assert_includes requirement.errors[:base], "A replacement only belongs to a substituted requirement"

    other_household = Household.new(name: "Other home")
    requirement.decision = :substituted
    requirement.replacement_ingredient = other_household.ingredients.build(name: "Outside", normalized_name: "outside")
    requirement.replacement_display_name = "Outside"
    requirement.replacement_decision = :unknown

    assert_not requirement.valid?
    assert_includes requirement.errors[:replacement_ingredient], "must belong to this household"
  end

  test "active rows keep a live source while superseded history may outlive it" do
    requirement = planned_meal_ingredients(:shared_salad_lettuce)
    requirement.source_recipe_ingredient = nil

    assert_not requirement.valid?
    assert_includes requirement.errors[:base], "An active requirement must keep its recipe source"
    assert_nil planned_meal_ingredients(:adjacent_free_text_history).source_recipe_ingredient_id
    assert_raises(ActiveRecord::StatementInvalid) do
      PlannedMealIngredient.connection.execute(
        "UPDATE planned_meal_ingredients SET source_recipe_ingredient_id = NULL WHERE id = #{requirement.id}"
      )
    end
  end

  test "a superseded requirement is paired, reasoned, and immutable afterwards" do
    requirement = planned_meal_ingredients(:sam_salad_lettuce)
    requirement.superseded_at = DECIDED_AT

    assert_not requirement.valid?
    assert_includes requirement.errors[:superseded_reason], "must accompany a supersession timestamp"

    requirement.superseded_reason = "someone_changed_their_mind"
    assert_not requirement.valid?
    assert_includes requirement.errors[:superseded_reason], "is not a supersession reason"

    requirement = planned_meal_ingredients(:sam_salad_lettuce)
    travel_to(DECIDED_AT) { requirement.supersede!("requirement_changed") }

    assert_equal DECIDED_AT, requirement.reload.superseded_at
    assert_not_predicate requirement, :active?
    assert_raises(ActiveRecord::RecordInvalid) { requirement.decide!(:missing) }
    assert_raises(ActiveRecord::RecordInvalid) { requirement.supersede!("source_removed") }
    assert_predicate requirement.reload, :on_hand?
  end

  test "active and history scopes separate current work from provenance" do
    plan = planned_meals(:adjacent_week)

    assert_equal [ planned_meal_ingredients(:adjacent_soup_carrots) ], plan.planned_meal_ingredients.active.to_a
    assert_equal [ planned_meal_ingredients(:adjacent_free_text_history) ], plan.planned_meal_ingredients.superseded.to_a
  end

  test "an obsolete requirement is discarded when untouched and kept as provenance once resolved" do
    untouched = planned_meal_ingredients(:shared_salad_lettuce)
    resolved = planned_meal_ingredients(:sam_salad_lettuce)

    assert_predicate untouched, :untouched?
    untouched.discard_or_supersede!("source_removed")
    assert_not PlannedMealIngredient.exists?(untouched.id)

    travel_to(DECIDED_AT) { resolved.discard_or_supersede!("source_removed") }
    assert_equal "source_removed", resolved.reload.superseded_reason
    assert_equal DECIDED_AT, resolved.superseded_at
    assert_predicate resolved, :on_hand?
  end

  test "requirement identity is measurable, raw-unit sensitive, or faithfully free text" do
    known = fingerprint(display_quantity: "1", unit: "cup", quantity: Rational(1))
    alias_of_known = fingerprint(display_quantity: "1", unit: "Cups", quantity: Rational(1))
    other_amount = fingerprint(display_quantity: "2", unit: "cup", quantity: Rational(2))

    assert_equal known, alias_of_known
    assert_not_equal known, other_amount

    sprigs = fingerprint(display_quantity: "2", unit: "sprigs", quantity: Rational(2))
    bunches = fingerprint(display_quantity: "2", unit: "bunches", quantity: Rational(2))
    assert_not_equal sprigs, bunches
    assert_not_equal known, fingerprint(display_quantity: "1", unit: "sprig", quantity: Rational(1))

    to_taste = fingerprint(display_quantity: "to taste", unit: nil, quantity: nil)
    assert_equal to_taste, fingerprint(display_quantity: "  To   Taste ", unit: nil, quantity: nil)
    assert_not_equal to_taste, fingerprint(display_quantity: "a pinch", unit: nil, quantity: nil)
  end

  test "the effective decision follows a substitution to its replacement" do
    substituted = planned_meal_ingredients(:soup_carrots_substituted)
    assert_equal "unknown", substituted.effective_decision

    substituted.decide_replacement!(:missing)
    assert_equal "missing", substituted.reload.effective_decision

    assert_equal "on_hand", planned_meal_ingredients(:sam_salad_lettuce).effective_decision
    assert_equal "not_needed", planned_meal_ingredients(:adjacent_soup_carrots).effective_decision
  end

  private
    def fingerprint(display_quantity:, unit:, quantity:)
      PlannedMealIngredient.requirement_fingerprint(
        ingredient_id: ingredients(:lettuce).id,
        display_quantity: display_quantity,
        unit: unit,
        quantity: quantity
      )
    end
end
