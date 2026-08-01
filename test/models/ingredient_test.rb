require "test_helper"

class IngredientTest < ActiveSupport::TestCase
  test "normalizes conservatively within a household" do
    assert_equal "rolled oats", Ingredient.normalize_name("  ROLLED   OATS ")
    assert_equal "strasse", Ingredient.normalize_name("STRAẞE")

    recipe = households(:home).recipes.create!(
      title: "Canonical identity",
      provenance_status: :personal,
      recipe_ingredients_attributes: [
        { display_name: "  CARROTS ", position: 1 },
        { display_name: "carrots", position: 2 },
        { display_name: "Carrot", position: 3 }
      ]
    )

    assert_equal recipe.recipe_ingredients.first.ingredient, recipe.recipe_ingredients.second.ingredient
    assert_not_equal recipe.recipe_ingredients.first.ingredient, recipe.recipe_ingredients.third.ingredient
    assert_equal "Carrots", recipe.recipe_ingredients.first.ingredient.name
  end

  test "identity uniqueness is household scoped at the database boundary" do
    index = ActiveRecord::Base.connection.indexes(:ingredients).find(&:unique)

    assert_equal %w[household_id normalized_name], index.columns
  end

  test "resolve reuses an existing normalized identity" do
    assert_no_difference "Ingredient.count" do
      assert_equal ingredients(:rolled_oats), Ingredient.resolve!(household: households(:home), name: "  ROLLED OATS ")
    end
  end


  test "manual nutrition allows blank attribution while sourced statuses require it" do
    ingredient = ingredients(:rolled_oats)
    ingredient.ingredient_nutrient_values.build(nutrient: nutrients(:protein), amount_per_100_grams: 0)
    ingredient.nutrition_provenance_status = :personal
    assert ingredient.valid?

    %i[verified adapted observed].each do |status|
      ingredient.nutrition_provenance_status = status
      ingredient.nutrition_source_name = nil
      assert_not ingredient.valid?
      assert_includes ingredient.errors[:nutrition_source_name], "can't be blank"
    end
  end

  test "recipe identity resolution preserves an existing nutrition profile" do
    ingredient = ingredients(:lettuce)
    before = [ ingredient.nutrition_source_name, ingredient.nutrition_provenance_status, ingredient.ingredient_nutrient_values.order(:nutrient_id).pluck(:nutrient_id, :amount_per_100_grams) ]

    assert_equal ingredient, Ingredient.resolve!(household: ingredient.household, name: " LETTUCE ")

    ingredient.reload
    assert_equal before, [ ingredient.nutrition_source_name, ingredient.nutrition_provenance_status, ingredient.ingredient_nutrient_values.order(:nutrient_id).pluck(:nutrient_id, :amount_per_100_grams) ]
  end
end
