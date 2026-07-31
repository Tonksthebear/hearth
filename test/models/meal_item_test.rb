require "test_helper"

class MealItemTest < ActiveSupport::TestCase
  test "requires exactly one source kind and matching reference" do
    item = MealItem.new(meal: meals(:alex_recipe_target_week), source_kind: :recipe, position: 1)
    assert_not item.valid?

    item.recipe = recipes(:salad)
    item.ingredient = ingredients(:rolled_oats)
    assert_not item.valid?

    item.ingredient = nil
    assert_predicate item, :valid?
  end

  test "feedback belongs only to a recipe-backed item" do
    item = meal_items(:alex_dinner_with_friends)
    item.build_recipe_feedback(body: "Not a recipe")

    assert_not item.valid?
    assert_includes item.errors[:recipe_feedback], "is only available for recipe items"
  end
end
