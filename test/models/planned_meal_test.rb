require "test_helper"

class PlannedMealTest < ActiveSupport::TestCase
  test "scopes plans by week and selected-person visibility" do
    week = MealWeek.for(
      household: households(:home),
      person: people(:one),
      date: "2026-07-27"
    )

    assert_includes week.planned_meals, planned_meals(:shared_target_week)
    assert_includes week.planned_meals, planned_meals(:alex_target_week)
    refute_includes week.planned_meals, planned_meals(:sam_target_week)
    refute_includes week.planned_meals, planned_meals(:adjacent_week)
  end

  test "requires person and recipe associations to match the household" do
    other_household = Household.new(name: "Other")
    other_person = other_household.people.build(name: "Other person")
    other_recipe = other_household.recipes.build(
      title: "Other recipe",
      source_name: "Test",
      provenance_status: :observed
    )

    planned_meal = PlannedMeal.new(
      household: households(:home),
      person: other_person,
      recipe: other_recipe,
      planned_on: Date.new(2026, 7, 27)
    )

    assert_not planned_meal.valid?
    assert_includes planned_meal.errors[:person], "must belong to this household"
    assert_includes planned_meal.errors[:recipe], "must belong to this household"
  end

  test "destroys assigned plans with a person but preserves shared plans" do
    person = people(:one)
    assigned_id = planned_meals(:alex_target_week).id
    shared_id = planned_meals(:shared_target_week).id

    person.destroy!

    assert_not PlannedMeal.exists?(assigned_id)
    assert PlannedMeal.exists?(shared_id)
  end


  test "shared plan converts independently once per person on the planned date" do
    plan = planned_meals(:shared_target_week)

    alex_meal = plan.convert_for!(people(:one), today: Date.new(2026, 7, 31))
    sam_meal = plan.convert_for!(people(:two), today: Date.new(2026, 7, 31))

    assert_equal plan.planned_on, alex_meal.eaten_on
    assert_equal plan.planned_on, sam_meal.eaten_on
    assert_equal [ people(:one).id, people(:two).id ].sort, plan.meals.reload.map(&:person_id).sort
    assert_equal alex_meal.id, plan.convert_for!(people(:one), today: Date.new(2026, 7, 31)).id
    assert_nil alex_meal.meal_items.first.portion_amount
    assert_equal "incomplete — portion needed", alex_meal.meal_items.first.nutrition_status
    assert_empty alex_meal.meal_items.first.meal_item_nutrient_values

    alex_meal.update!(notes: "Alex changed this meal")
    assert_nil sam_meal.reload.notes
    alex_meal.destroy!
    assert Meal.exists?(sam_meal.id)
  end

  test "future and invisible plans cannot convert" do
    assert_raises(ActiveRecord::RecordInvalid) do
      planned_meals(:adjacent_week).convert_for!(people(:one), today: Date.new(2026, 7, 31))
    end
    assert_raises(ActiveRecord::RecordInvalid) do
      planned_meals(:sam_target_week).convert_for!(people(:one), today: Date.new(2026, 7, 31))
    end
  end

  test "referenced plan cannot be destroyed" do
    plan = planned_meals(:shared_target_week)
    plan.convert_for!(people(:one), today: Date.new(2026, 7, 31))

    assert_raises(ActiveRecord::DeleteRestrictionError) { plan.destroy! }
  end

  test "a new plan snapshots one full-yield requirement per recipe line before shopping runs" do
    plan = PlannedMeal.create!(
      household: households(:home),
      recipe: recipes(:porridge),
      planned_on: Date.new(2026, 7, 31)
    )

    requirements = plan.planned_meal_ingredients.active.to_a
    assert_equal [ "Rolled oats", "Blueberries" ], requirements.map(&:display_name)
    assert_equal [ 1, 2 ], requirements.map(&:position)
    assert_equal [ Rational(1), Rational(1, 2) ], requirements.map(&:quantity)
    assert_equal [ recipes(:porridge).id ], requirements.map(&:source_recipe_id).uniq
    assert_equal [ true ], requirements.map(&:untouched?).uniq
    assert_equal 1, plan.recipe_scale
  end

  test "ingredient snapshots commit before shopping reconciliation" do
    order = []
    plan = PlannedMeal.new(household: households(:home), recipe: recipes(:porridge), planned_on: Date.new(2026, 7, 31))
    plan.singleton_class.prepend(Module.new do
      define_method(:reconcile_ingredient_snapshots) { order << :ingredient_snapshots; super() }
      define_method(:reconcile_shopping_lists) { order << :shopping_lists; super() }
    end)

    plan.save!
    plan.update!(planned_on: Date.new(2026, 8, 1))

    assert_equal %i[ ingredient_snapshots shopping_lists ingredient_snapshots shopping_lists ], order
  end

  test "scale multiplies required quantities exactly without rewriting the authored amount" do
    plan = planned_meals(:shared_target_week)

    plan.update!(recipe_scale: "1.5")

    requirement = plan.planned_meal_ingredients.active.sole
    assert_equal Rational(3, 2), requirement.quantity
    assert_equal "1", requirement.display_quantity
    assert_equal "head", requirement.unit
  end

  test "a plan requires a positive scale" do
    plan = planned_meals(:shared_target_week)
    plan.recipe_scale = 0

    assert_not plan.valid?
    assert_includes plan.errors[:recipe_scale], "must be greater than 0"
  end

  test "moving a plan keeps its decisions and still reconciles both shopping weeks" do
    plan = planned_meals(:sam_target_week)
    decided = planned_meal_ingredients(:sam_salad_lettuce)
    departed_week = ShoppingList.for(household: households(:home), date: plan.planned_on)
    assert ShoppingListItemSource.exists?(planned_meal: plan)

    plan.update!(planned_on: Date.new(2026, 8, 4))

    assert_equal [ decided.id ], plan.planned_meal_ingredients.active.ids
    assert_predicate decided.reload, :on_hand?
    assert_empty ShoppingListItemSource.joins(:shopping_list_item)
      .where(planned_meal: plan, shopping_list_items: { shopping_list_id: departed_week.id })
    assert_equal Date.new(2026, 8, 3),
      ShoppingListItemSource.where(planned_meal: plan).sole.shopping_list_item.shopping_list.week_start
  end

  test "changing the recipe supersedes resolved decisions and issues fresh unknown requirements" do
    plan = planned_meals(:sam_target_week)
    decided = planned_meal_ingredients(:sam_salad_lettuce)
    superseded_at = Time.utc(2026, 7, 30, 8)

    travel_to(superseded_at) { plan.update!(recipe: recipes(:porridge)) }

    assert_equal "recipe_changed", decided.reload.superseded_reason
    assert_equal superseded_at, decided.superseded_at
    assert_predicate decided, :on_hand?
    assert_equal [ "Rolled oats", "Blueberries" ], plan.planned_meal_ingredients.active.map(&:display_name)
    assert_equal [ true ], plan.planned_meal_ingredients.active.map(&:untouched?).uniq
  end

  test "changing the scale supersedes resolved decisions with a scale reason" do
    plan = planned_meals(:sam_target_week)
    decided = planned_meal_ingredients(:sam_salad_lettuce)

    plan.update!(recipe_scale: 2)

    assert_equal "recipe_scale_changed", decided.reload.superseded_reason
    fresh = plan.planned_meal_ingredients.active.sole
    assert_equal Rational(2), fresh.quantity
    assert_predicate fresh, :untouched?
  end

  test "an untouched requirement is discarded rather than kept when it goes obsolete" do
    plan = planned_meals(:shared_target_week)
    untouched = planned_meal_ingredients(:shared_salad_lettuce)

    plan.update!(recipe: recipes(:alex_only))

    assert_not PlannedMealIngredient.exists?(untouched.id)
    assert_empty plan.planned_meal_ingredients.reload
  end

  test "reconciling repeatedly is a no-op that keeps one active row per source" do
    plan = planned_meals(:sam_target_week)

    assert_no_difference "PlannedMealIngredient.count" do
      3.times { plan.reconcile_ingredient_snapshots! }
    end
    assert_equal [ planned_meal_ingredients(:sam_salad_lettuce).id ], plan.planned_meal_ingredients.active.ids
    assert_predicate planned_meal_ingredients(:sam_salad_lettuce).reload, :on_hand?
  end

  test "deleting a plan destroys its active and superseded decision history" do
    plan = planned_meals(:adjacent_week)

    assert_difference "PlannedMealIngredient.count", -2 do
      plan.destroy!
    end
  end
end
