require "test_helper"

class Recipe::NutritionTest < ActiveSupport::TestCase
  test "derives deterministic per-serving amounts from explicit grams" do
    recipe = households(:home).recipes.create!(
      title: "Protein math",
      provenance_status: :personal,
      serving_count: 2,
      recipe_ingredients_attributes: [ { display_name: "Lettuce", gram_weight: 125, position: 1 } ]
    )

    result = recipe.nutrition.result_for(nutrients(:protein))

    assert_equal BigDecimal("6.175"), result.amount
    assert result.complete
    assert_equal "6.18 g", result.formatted_amount
  end

  test "legacy recipe values do not override ingredient-derived nutrition" do
    recipe = recipes(:salad)
    recipe.recipe_nutrient_values.create!(nutrient: nutrients(:protein), amount: 0)

    protein = recipe.nutrition.result_for(nutrients(:protein))
    energy = recipe.nutrition.result_for(nutrients(:energy))

    assert_equal BigDecimal("6.175"), protein.amount
    assert_equal BigDecimal("0"), energy.amount
  end

  test "missing serving count gram weight or ingredient value remains visible" do
    recipe = recipes(:porridge)
    recipe.serving_count = nil
    missing_servings = recipe.nutrition.result_for(nutrients(:protein))
    assert_nil missing_servings.amount
    assert_not missing_servings.complete

    recipe.serving_count = 2
    recipe.recipe_ingredients.first.gram_weight = 125
    partial = recipe.nutrition.result_for(nutrients(:protein))
    assert_nil partial.amount
    assert_not partial.complete
  end
end
