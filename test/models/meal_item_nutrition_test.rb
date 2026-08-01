require "test_helper"

class MealItemNutritionTest < ActiveSupport::TestCase
  test "snapshots deterministic recipe nutrition and scales by servings" do
    meal = people(:one).meals.create!(
      household: households(:home),
      eaten_on: Date.new(2026, 7, 31),
      meal_items_attributes: [ { source_kind: :recipe, recipe: recipes(:salad), portion_amount: 1.5, portion_unit: "servings" } ]
    )
    item = meal.meal_items.first

    assert item.nutrition_complete?
    assert item.nutrition_estimated?
    assert_equal 6, item.meal_item_nutrient_values.count
    assert_equal BigDecimal("9.2625"), item.meal_item_nutrient_values.find_by!(snapshot_key: "protein").amount
  end

  test "upstream and note-only edits do not rewrite history but portion correction does" do
    item = meal_items(:alex_salad)
    before = item.meal_item_nutrient_values.order(:snapshot_key).map { |value| value.attributes.except("id", "created_at", "updated_at") }

    item.recipe.update!(title: "Changed title", serving_count: 4)
    item.ingredient&.update!(nutrition_source_name: "Changed source")
    nutrients(:protein).update!(name: "Changed protein label")
    item.update!(notes: "Meal note only")

    assert_equal before, item.reload.meal_item_nutrient_values.order(:snapshot_key).map { |value| value.attributes.except("id", "created_at", "updated_at") }

    item.update!(portion_amount: 2)
    assert_equal BigDecimal("6.175"), item.meal_item_nutrient_values.find_by!(snapshot_key: "protein").amount
  end

  test "unsupported or absent portions remain incomplete without false zero rows" do
    meal = people(:one).meals.create!(
      household: households(:home), eaten_on: Date.new(2026, 7, 31),
      meal_items_attributes: [ { source_kind: :recipe, recipe: recipes(:salad), portion_amount: 1, portion_unit: "bowl" } ]
    )
    item = meal.meal_items.first

    assert_not item.nutrition_complete?
    assert_empty item.meal_item_nutrient_values
    assert_equal "unavailable", item.nutrition_status
  end
end
