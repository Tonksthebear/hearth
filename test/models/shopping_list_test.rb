require "test_helper"

class ShoppingListTest < ActiveSupport::TestCase
  WEEK_START = Date.new(2026, 9, 7)

  test "aggregates measurable deficits on the canonical unit while the generic count group stays separate" do
    first = recipe_with(title: "First soup", ingredients: [ { display_quantity: "1 1/2", unit: "cup", display_name: "Carrots" } ])
    second = recipe_with(
      title: "Second soup",
      ingredients: [
        { display_quantity: "2", unit: "cup", display_name: " carrots " },
        { display_quantity: "1", unit: "Cup", display_name: "Carrots" },
        { display_quantity: "1", unit: nil, display_name: "Carrots" }
      ]
    )
    plan_with(recipe: first, planned_on: WEEK_START)
    plan_with(recipe: second, planned_on: WEEK_START + 1.day)

    list = reconciled_list

    # Deliberate inversion of the previous raw-unit boundary: "cup" and "Cup" are
    # one canonical unit, so they aggregate instead of producing duplicate rows.
    merged = list.items.find_by!(name: "Carrots", quantity: "4.5", unit: "cup")
    assert_equal 3, merged.shopping_list_item_sources.count
    assert_equal [ first.id, second.id, second.id ], merged.shopping_list_item_sources.map { |source| source.planned_meal.recipe_id }
    counted = list.items.find_by!(name: "Carrots", quantity: "1", unit: nil)
    assert_equal 1, counted.shopping_list_item_sources.count
    assert_equal 2, list.items.where(generated_key: [ merged.generated_key, counted.generated_key ]).count
  end

  test "an unresolved requirement produces no shopping work" do
    recipe = recipe_with(title: "Unknown soup", ingredients: [ { display_quantity: "1", unit: "cup", display_name: "Broth" } ])
    plan_with(recipe: recipe, planned_on: WEEK_START, decision: :unknown)

    assert_empty reconciled_list.items.where.not(generated_key: nil)
  end

  test "earlier dated demand wins and the later meal shops only its shortfall" do
    pantry_confirmed("Beans", quantity: "3", unit: "can")
    recipe = recipe_with(title: "Chili", ingredients: [ { display_quantity: "2", unit: "can", display_name: "Beans" } ])
    plan_with(recipe: recipe, planned_on: WEEK_START, decision: :on_hand)
    later = plan_with(recipe: recipe, planned_on: WEEK_START + 4.days, decision: :missing)

    item = reconciled_list.items.find_by!(name: "Beans")
    assert_equal [ "1", "can" ], item.values_at(:quantity, :unit)
    assert_equal [ later.id ], item.planned_meals.ids
    assert_equal :missing, item.shopping_list_item_sources.sole.confirmation_state
  end

  test "an on_hand requirement that loses its allocation still produces a deficit row" do
    pantry_confirmed("Beans", quantity: "2", unit: "can")
    recipe = recipe_with(title: "Chili", ingredients: [ { display_quantity: "2", unit: "can", display_name: "Beans" } ])
    plan_with(recipe: recipe, planned_on: WEEK_START, decision: :on_hand)
    plan_with(recipe: recipe, planned_on: WEEK_START + 4.days, decision: :on_hand)

    source = reconciled_list.items.find_by!(name: "Beans", quantity: "2", unit: "can").shopping_list_item_sources.sole
    assert_equal :on_hand, source.confirmation_state
    assert source.household_confirmed?
  end

  test "not needed fully allocated and stocked requirements are excluded" do
    pantry_confirmed("Rice", quantity: "4", unit: "cup")
    stocked = recipe_with(title: "Rice bowl", ingredients: [ { display_quantity: "2", unit: "cup", display_name: "Rice" } ])
    skipped = recipe_with(title: "Garnish", ingredients: [ { display_quantity: "1", unit: "cup", display_name: "Parsley" } ])
    plan_with(recipe: stocked, planned_on: WEEK_START, decision: :on_hand)
    plan_with(recipe: skipped, planned_on: WEEK_START + 1.day, decision: :not_needed)

    assert_empty reconciled_list.items.where.not(generated_key: nil)
  end

  test "definitive pantry evidence resolves an unknown decision into an unconfirmed deficit" do
    pantry_out("Kale")
    recipe = recipe_with(title: "Greens", ingredients: [ { display_quantity: "2", unit: "head", display_name: "Kale" } ])
    plan_with(recipe: recipe, planned_on: WEEK_START, decision: :unknown)

    source = reconciled_list.items.find_by!(name: "Kale", quantity: "2", unit: "head").shopping_list_item_sources.sole
    assert_equal :pantry_evidence, source.confirmation_state
    refute source.household_confirmed?
    assert_equal "From pantry evidence", source.confirmation_label
  end

  test "unparseable free text shops faithfully only when the household says it is missing" do
    recipe = recipe_with(title: "Tomato soup", ingredients: [ { display_quantity: "to taste", unit: nil, display_name: "Salt" } ])
    unresolved = plan_with(recipe: recipe, planned_on: WEEK_START, decision: :unknown)
    assert_empty reconciled_list.items.where.not(generated_key: nil)

    decide_all(unresolved, :missing)
    second = plan_with(recipe: recipe, planned_on: WEEK_START + 1.day)

    items = reconciled_list.items.where(name: "Salt").to_a
    assert_equal [ "to taste", "to taste" ], items.map(&:quantity)
    assert_equal [ nil, nil ], items.map(&:unit)
    assert_equal [ unresolved.id, second.id ].sort, items.flat_map { |item| item.planned_meals.ids }.sort
  end

  test "a substitution shops for the replacement ingredient name and amount" do
    recipe = recipe_with(title: "Pasta", ingredients: [ { display_quantity: "1", unit: "cup", display_name: "Parmesan" } ])
    plan = households(:home).planned_meals.create!(recipe:, planned_on: WEEK_START)
    replacement = Ingredient.resolve!(household: households(:home), name: "Nutritional yeast")
    requirement = plan.planned_meal_ingredients.active.sole
    requirement.substitute!(ingredient: replacement, display_quantity: "2", unit: "cup")
    requirement.decide_replacement!(:missing)

    item = reconciled_list.items.find_by!(name: "Nutritional yeast")
    assert_equal [ "2", "cup", replacement.id ], item.values_at(:quantity, :unit, :ingredient_id)
    source = item.shopping_list_item_sources.sole
    assert source.substituted?
    assert_equal "Nutritional yeast", source.replacement_display_name
    assert_equal :missing, source.confirmation_state
  end

  test "household shopping counts every plan once including another person's" do
    recipe = recipe_with(title: "Lentils", ingredients: [ { display_quantity: "1", unit: "cup", display_name: "Lentils" } ])
    shared = plan_with(recipe: recipe, planned_on: WEEK_START)
    other = plan_with(recipe: recipe, planned_on: WEEK_START + 1.day, person: people(:two))

    item = reconciled_list.items.find_by!(name: "Lentils")
    assert_equal "2", item.quantity
    assert_equal [ shared.id, other.id ], item.planned_meals.ids
    assert_equal 2, item.shopping_list_item_sources.count
  end

  test "the cold switch drops untouched legacy rows and keeps manual edited and completed intent" do
    recipe = recipe_with(title: "Cutover", ingredients: [ { display_quantity: "1", unit: "cup", display_name: "Tomatoes" } ])
    plan_with(recipe: recipe, planned_on: WEEK_START, decision: :unknown)
    list = households(:home).shopping_lists.create_or_find_by!(week_start: WEEK_START)
    legacy_key = [ "ingredient", nil, "cup" ].to_json
    untouched = list.items.create!(name: "Legacy tomatoes", quantity: "1", unit: "cup", generated_key: legacy_key)
    edited = list.items.create!(name: "Edited tomatoes", quantity: "2", unit: "cup",
      generated_key: [ "ingredient", nil, "can" ].to_json, user_managed_at: Time.current)
    completed = list.items.create!(name: "Completed tomatoes", quantity: "3", unit: "cup",
      generated_key: [ "source", 1, 2 ].to_json, completed_at: Time.current)
    manual = list.items.create!(name: "Party napkins", user_managed_at: Time.current)

    list.reconcile!

    refute ShoppingListItem.exists?(untouched.id)
    assert_equal [ "Edited tomatoes", "2" ], edited.reload.values_at(:name, :quantity)
    assert completed.reload.completed?
    assert_equal "Party napkins", manual.reload.name
    assert_empty list.items.where(generated_key: legacy_key)
    assert_empty list.items.where.not(generated_key: nil).where.not(id: [ edited.id, completed.id ])
  end

  test "reconciliation is idempotent and refreshes an untouched row from its remaining source" do
    first_recipe = recipe_with(title: "First", ingredients: [ { display_quantity: "2", unit: "bag", display_name: "Apples" } ])
    second_recipe = recipe_with(title: "Second", ingredients: [ { display_quantity: "3", unit: "bag", display_name: "APPLES" } ])
    first_plan = plan_with(recipe: first_recipe, planned_on: WEEK_START)
    plan_with(recipe: second_recipe, planned_on: WEEK_START + 1.day)
    list = reconciled_list
    item = list.items.find_by!(unit: "bag")
    item.complete!
    item_ids = list.items.ids
    source_ids = ShoppingListItemSource.where(shopping_list_item: list.items).ids

    list.reconcile!
    assert_equal item_ids, list.items.ids
    assert_equal source_ids, ShoppingListItemSource.where(shopping_list_item: list.items).ids

    first_plan.destroy!
    item.reload
    assert_equal "APPLES", item.name
    assert_equal "3", item.quantity
    assert item.completed?
    assert_equal 1, item.shopping_list_item_sources.count
  end

  test "source disappearance removes only untouched unchecked rows and preserves edited and completed intent" do
    recipe = recipe_with(title: "Intent", ingredients: [ { display_quantity: "2", unit: "cup", display_name: "Kale" } ])
    untouched_plan = plan_with(recipe: recipe, planned_on: WEEK_START)
    list = reconciled_list
    untouched_item_id = list.items.find_by!(name: "Kale").id
    untouched_plan.destroy!
    refute ShoppingListItem.exists?(untouched_item_id)

    edited_plan = plan_with(recipe: recipe, planned_on: WEEK_START)
    edited = reconciled_list.items.find_by!(name: "Kale")
    assert edited.apply_user_attributes(name: "Farm kale", quantity: "4", unit: "bunch", notes: "Keep this")
    edited_plan.destroy!
    assert_equal [ "Farm kale", "4", "bunch", "Keep this" ], edited.reload.values_at(:name, :quantity, :unit, :notes)
    assert_empty edited.shopping_list_item_sources

    returning_plan = plan_with(recipe: recipe, planned_on: WEEK_START + 1.day)
    reconciled_list
    edited.reload
    assert_equal "Farm kale", edited.name
    assert_equal 1, edited.shopping_list_item_sources.count
    edited.complete!
    returning_plan.destroy!
    assert edited.reload.completed?

    plan_with(recipe: recipe, planned_on: WEEK_START + 2.days)
    reconciled_list
    assert edited.reload.completed?
    assert_equal 1, list.items.where(generated_key: edited.generated_key).count
    edited.uncomplete!
    refute edited.reload.completed?
  end

  test "new weeks reset completion and old missing periods are not materialized by cleanup" do
    recipe = recipe_with(title: "Weekly", ingredients: [ { display_quantity: "1", unit: "jar", display_name: "Tahini" } ])
    plan = plan_with(recipe: recipe, planned_on: WEEK_START)
    first_list = reconciled_list
    first_list.items.first.complete!

    plan.update!(planned_on: WEEK_START + 7.days)
    second_list = reconciled_list(WEEK_START + 7.days)
    refute second_list.items.first.completed?
    assert first_list.reload.items.first.completed?

    first_list.destroy!
    second_list.destroy!
    assert_no_difference [ "ShoppingList.count", "ShoppingListItem.count", "ShoppingListItemSource.count" ] do
      plan.destroy!
    end
  end

  test "manual items validate and survive unrelated reconciliation while observed meals do not participate" do
    list = households(:home).shopping_lists.create!(week_start: WEEK_START)
    manual = list.items.build
    refute manual.apply_user_attributes(name: "", quantity: "1", unit: "box", notes: "Required")
    assert_includes manual.errors[:name], "can't be blank"
    assert manual.apply_user_attributes(name: "Tea", quantity: "1", unit: "box", notes: "Decaf")

    counts = [ list.items.count, ShoppingListItemSource.count ]
    meal = households(:home).meals.create!(
      person: people(:one),
      eaten_on: WEEK_START,
      meal_items_attributes: [ { source_kind: :free_text, snapshot_label: "Ate carrots", position: 1 } ]
    )
    meal.update!(notes: "Still observed")
    meal.destroy!
    list.reconcile!

    assert_equal [ "Tea", "1", "box", "Decaf" ], manual.reload.values_at(:name, :quantity, :unit, :notes)
    assert_equal counts.first, list.items.count
    assert_equal counts.second, ShoppingListItemSource.count
  end

  test "plan date and recipe changes reconcile new periods without materializing a missing old list" do
    first_recipe = recipe_with(title: "Old recipe", ingredients: [ { display_quantity: "1", unit: "box", display_name: "Rice" } ])
    second_recipe = recipe_with(title: "New recipe", ingredients: [ { display_quantity: "2", unit: "can", display_name: "Beans" } ])
    plan = plan_with(recipe: first_recipe, planned_on: WEEK_START)
    reconciled_list.destroy!

    plan.update!(planned_on: WEEK_START + 7.days)
    refute ShoppingList.exists?(household: households(:home), week_start: WEEK_START)
    new_list = reconciled_list(WEEK_START + 7.days)
    assert new_list.items.exists?(name: "Rice")

    plan.update!(recipe: second_recipe)
    decide_all(plan, :missing)
    new_list.reconcile!
    refute new_list.items.exists?(name: "Rice")
    assert new_list.items.exists?(name: "Beans", quantity: "2", unit: "can")
    assert_equal [ plan.id ], new_list.items.find_by!(name: "Beans").planned_meals.ids
  end

  test "reconcile exposes the single allocation used for ownership without building a second engine" do
    recipe = recipe_with(title: "Ownership chili", ingredients: [ { display_quantity: "2", unit: "can", display_name: "Beans" } ])
    plan_with(recipe: recipe, planned_on: WEEK_START, decision: :missing)
    list = reconciled_list

    assert list.allocation.present?
    assert_kind_of Household::PantryAllocation, list.allocation
    first_object_id = list.allocation.object_id
    assert_equal first_object_id, list.allocation.object_id
    assert_equal :shopping_needed, list.allocation.readiness_for(PlannedMeal.order(:id).last).state
  end

  test "converting a plan removes its open deficit rows only at the next explicit reconciliation" do
    recipe = recipe_with(
      title: "Convertible",
      ingredients: [
        { display_quantity: "1", unit: "cup", display_name: "Quinoa" },
        { display_quantity: "2", unit: "cup", display_name: "Farro" }
      ]
    )
    plan = plan_with(recipe: recipe, planned_on: WEEK_START)
    list = reconciled_list
    generated = list.items.find_by!(name: "Quinoa")
    edited = list.items.find_by!(name: "Farro")
    assert edited.apply_user_attributes(notes: "Bulk bin")
    manual = list.items.create!(name: "Party napkins", user_managed_at: Time.current)
    completed = list.items.create!(name: "Completed row", generated_key: [ "deficit", 0, "cup" ].to_json, completed_at: Time.current)

    plan.convert_for!(people(:one), today: WEEK_START)

    # convert_for! creates a Meal without saving the plan, so no PlannedMeal
    # commit callback fires and the persisted list is untouched until a visit.
    assert_equal [ generated.id, edited.id, manual.id, completed.id ].sort, list.reload.items.ids.sort

    list.reconcile!

    refute ShoppingListItem.exists?(generated.id)
    assert_equal "Bulk bin", edited.reload.notes
    assert_empty edited.shopping_list_item_sources
    assert_equal "Party napkins", manual.reload.name
    assert completed.reload.completed?
  end

  private
    def recipe_with(title:, ingredients:)
      households(:home).recipes.create!(
        title: title,
        source_name: "Test",
        provenance_status: :observed,
        recipe_ingredients_attributes: ingredients.map.with_index(1) { |attributes, position| attributes.merge(position:) }
      )
    end

    def plan_with(recipe:, planned_on:, decision: :missing, person: nil)
      plan = households(:home).planned_meals.create!(recipe:, planned_on:, person:)
      decide_all(plan, decision)
    end

    def decide_all(plan, decision)
      plan.planned_meal_ingredients.active.each { |requirement| requirement.decide!(decision) }
      plan
    end

    def reconciled_list(date = WEEK_START)
      ShoppingList.for(household: households(:home), date: date)
    end

    def pantry_confirmed(name, quantity:, unit:)
      pantry_row(name).confirm!(quantity: quantity, unit: unit, source: "pantry_check", confirmed_by: people(:without_login))
    end

    def pantry_out(name)
      pantry_row(name).mark_out!(source: "pantry_check", confirmed_by: people(:without_login))
    end

    def pantry_row(name)
      PantryItem.for(household: households(:home), ingredient: Ingredient.resolve!(household: households(:home), name: name))
    end
end
