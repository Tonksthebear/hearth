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
end
