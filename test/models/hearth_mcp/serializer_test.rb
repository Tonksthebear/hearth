require "test_helper"

class HearthMcp::SerializerTest < ActiveSupport::TestCase
  test "recipe detail serializes preloaded normalized ingredient data without queries" do
    recipe = Recipe.includes(recipe_ingredients: :ingredient).find(recipes(:porridge).id)
    serialized = nil

    assert_queries_count(0) do
      serialized = HearthMcp::Serializer.recipe(recipe, detail: true)
    end

    assert_equal recipe.recipe_ingredients.sort_by { |line| [ line.position, line.id ] }.map(&:id),
      serialized.fetch(:ingredients).pluck(:id)
    assert_equal %i[
      id ingredient_id ingredient_name display_name display_quantity
      quantity_numerator quantity_denominator unit notes position
    ], serialized.fetch(:ingredients).first.keys
  end


  test "meal serializes scoped nested event data" do
    meal = Meal.includes(meal_items: [ :recipe, :ingredient, :recipe_feedback, :meal_item_nutrient_values ]).find(meals(:alex_recipe_target_week).id)

    serialized = HearthMcp::Serializer.meal(meal)

    assert_equal meal.id, serialized[:id]
    assert_equal meal.person_id, serialized[:person_id]
    assert_equal "recipe", serialized.dig(:items, 0, :source_kind)
    assert_equal meal_items(:alex_salad).snapshot_label, serialized.dig(:items, 0, :snapshot_label)
    assert_equal recipe_feedbacks(:alex_salad_feedback).body, serialized.dig(:items, 0, :recipe_feedback, :body)
    assert_equal true, serialized.dig(:items, 0, :nutrition_complete)
    protein = serialized.dig(:items, 0, :nutrition).find { |value| value[:key] == "protein" }
    assert_equal "9.2625", protein[:amount]
    assert_equal "estimated", protein[:calculation_kind]
  end
end
