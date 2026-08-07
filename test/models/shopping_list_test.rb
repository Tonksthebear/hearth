require "test_helper"

class ShoppingListTest < ActiveSupport::TestCase
  WEEK_START = Date.new(2026, 9, 7)

  test "aggregates canonical ingredients only across exact units and records every source" do
    recipe_one = recipe_with(
      title: "First soup",
      ingredients: [
        { display_quantity: "1 1/2", unit: "cup", display_name: "Carrots" },
        { display_quantity: "to taste", unit: "pinch", display_name: "Salt" }
      ]
    )
    recipe_two = recipe_with(
      title: "Second soup",
      ingredients: [
        { display_quantity: "2", unit: "cup", display_name: " carrots " },
        { display_quantity: "1", unit: "Cup", display_name: "Carrots" },
        { display_quantity: "1", unit: nil, display_name: "Carrots" },
        { display_quantity: "as needed", unit: "pinch", display_name: "Salt" }
      ]
    )

    households(:home).planned_meals.create!(recipe: recipe_one, planned_on: WEEK_START)
    households(:home).planned_meals.create!(recipe: recipe_two, planned_on: WEEK_START + 1.day)
    list = ShoppingList.existing_for(household: households(:home), date: WEEK_START)

    cup = list.items.find_by!(name: "Carrots", quantity: "3.5", unit: "cup")
    assert_equal 2, cup.shopping_list_item_sources.count
    assert_equal [ recipe_one.id, recipe_two.id ], cup.shopping_list_item_sources.map { |source| source.planned_meal.recipe_id }.sort
    assert list.items.exists?(quantity: "1", unit: "Cup")
    assert list.items.exists?(quantity: "1", unit: nil)
    assert_equal 2, list.items.where(ingredient: households(:home).ingredients.find_by!(normalized_name: "salt")).count
  end

  test "reconciliation is idempotent and refreshes an untouched row from its ordered remaining source" do
    first_recipe = recipe_with(title: "First", ingredients: [ { display_quantity: "2", unit: "bag", display_name: "Apples" } ])
    second_recipe = recipe_with(title: "Second", ingredients: [ { display_quantity: "3", unit: "bag", display_name: "APPLES" } ])
    first_plan = households(:home).planned_meals.create!(recipe: first_recipe, planned_on: WEEK_START)
    households(:home).planned_meals.create!(recipe: second_recipe, planned_on: WEEK_START + 1.day)
    list = ShoppingList.existing_for(household: households(:home), date: WEEK_START)
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
    recipe = recipe_with(title: "Intent", ingredients: [ { display_quantity: "2", unit: "bunch", display_name: "Kale" } ])
    untouched_plan = households(:home).planned_meals.create!(recipe:, planned_on: WEEK_START)
    list = ShoppingList.existing_for(household: households(:home), date: WEEK_START)
    untouched_item_id = list.items.find_by!(name: "Kale").id
    untouched_plan.destroy!
    refute ShoppingListItem.exists?(untouched_item_id)

    edited_plan = households(:home).planned_meals.create!(recipe:, planned_on: WEEK_START)
    edited = list.reload.items.find_by!(name: "Kale")
    assert edited.apply_user_attributes(name: "Farm kale", quantity: "4", unit: "bunch", notes: "Keep this")
    edited_plan.destroy!
    assert_equal [ "Farm kale", "4", "bunch", "Keep this" ], edited.reload.values_at(:name, :quantity, :unit, :notes)
    assert_empty edited.shopping_list_item_sources

    returning_plan = households(:home).planned_meals.create!(recipe:, planned_on: WEEK_START + 1.day)
    edited.reload
    assert_equal "Farm kale", edited.name
    assert_equal 1, edited.shopping_list_item_sources.count
    edited.complete!
    returning_plan.destroy!
    assert edited.reload.completed?

    households(:home).planned_meals.create!(recipe:, planned_on: WEEK_START + 2.days)
    assert edited.reload.completed?
    assert_equal 1, list.items.where(generated_key: edited.generated_key).count
    edited.uncomplete!
    refute edited.reload.completed?
  end

  test "new weeks reset completion and old missing periods are not materialized by cleanup" do
    recipe = recipe_with(title: "Weekly", ingredients: [ { display_quantity: "1", unit: "jar", display_name: "Tahini" } ])
    plan = households(:home).planned_meals.create!(recipe:, planned_on: WEEK_START)
    first_list = ShoppingList.existing_for(household: households(:home), date: WEEK_START)
    first_list.items.first.complete!

    plan.update!(planned_on: WEEK_START + 7.days)
    second_list = ShoppingList.existing_for(household: households(:home), date: WEEK_START + 7.days)
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

    counts = [ list.items.count, ShoppingListItemSource.count, list.updated_at ]
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

  test "separates remaining and completed display items" do
    list = ShoppingList.for(household: households(:home), date: Date.new(2026, 7, 27))

    assert list.remaining_items.any?
    assert list.remaining_items.none?(&:completed?)
    assert_equal [ shopping_list_items(:completed_foil) ], list.completed_items
    assert list.completed_items.all?(&:completed?)
  end

  test "plan date and recipe changes reconcile new periods without materializing a missing old list" do
    first_recipe = recipe_with(title: "Old recipe", ingredients: [ { display_quantity: "1", unit: "box", display_name: "Rice" } ])
    second_recipe = recipe_with(title: "New recipe", ingredients: [ { display_quantity: "2", unit: "can", display_name: "Beans" } ])
    plan = households(:home).planned_meals.create!(recipe: first_recipe, planned_on: WEEK_START)
    old_list = ShoppingList.existing_for(household: households(:home), date: WEEK_START)
    old_list.destroy!

    plan.update!(planned_on: WEEK_START + 7.days)
    refute ShoppingList.exists?(household: households(:home), week_start: WEEK_START)
    new_list = ShoppingList.existing_for(household: households(:home), date: WEEK_START + 7.days)
    assert new_list.items.exists?(name: "Rice")

    plan.update!(recipe: second_recipe)
    refute new_list.reload.items.exists?(name: "Rice")
    assert new_list.items.exists?(name: "Beans", quantity: "2", unit: "can")
    assert_equal [ plan.id ], new_list.items.find_by!(name: "Beans").shopping_list_item_sources.pluck(:planned_meal_id)
  end

  test "converting a plan to an observed meal leaves its sole shopping requirement unchanged" do
    plan = planned_meals(:shared_target_week)
    list = ShoppingList.for(household: households(:home), date: plan.planned_on)
    item_ids = list.items.ids
    source_ids = ShoppingListItemSource.where(shopping_list_item: list.items).ids
    timestamps = [ list.updated_at, *list.items.order(:id).pluck(:updated_at) ]

    meal = plan.convert_for!(people(:one), today: plan.planned_on)

    assert_equal plan, meal.planned_meal
    assert_equal item_ids, list.reload.items.ids
    assert_equal source_ids, ShoppingListItemSource.where(shopping_list_item: list.items).ids
    assert_equal timestamps, [ list.updated_at, *list.items.order(:id).pluck(:updated_at) ]
    assert ShoppingListItemSource.exists?(planned_meal: plan)
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
end
