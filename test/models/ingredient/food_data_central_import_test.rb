require "test_helper"

class Ingredient::FoodDataCentralImportTest < ActiveSupport::TestCase
  test "imports only recognized identifier and unit pairs with attribution" do
    ingredient = ingredients(:rolled_oats)
    response = success_response({
      foodNutrients: [
        { nutrient: { id: 1003, unitName: "g" }, amount: 9.88 },
        { nutrient: { id: 9999, unitName: "g" }, amount: 123 }
      ]
    })

    Ingredient::FoodDataCentralImport.new(
      ingredient:, food_id: 123, api_key: "protected-test-key", requester: ->(_uri) { response }
    ).import!

    assert_equal "123", ingredient.reload.food_data_central_id
    assert_equal "USDA FoodData Central", ingredient.nutrition_source_name
    assert ingredient.nutrition_verified?
    assert_equal BigDecimal("9.88"), ingredient.ingredient_nutrient_values.find_by!(nutrient: nutrients(:protein)).amount_per_100_grams
    assert_equal 1, ingredient.ingredient_nutrient_values.count
  end

  test "requires explicit identity and a protected key" do
    error = assert_raises(ArgumentError) do
      Ingredient::FoodDataCentralImport.new(ingredient: ingredients(:rolled_oats), food_id: "", api_key: "key").import!
    end
    assert_not_includes error.message, "key"

    error = assert_raises(Ingredient::FoodDataCentralImport::ImportError) do
      Ingredient::FoodDataCentralImport.new(ingredient: ingredients(:rolled_oats), food_id: 123, api_key: nil).import!
    end
    assert_not_includes error.message, "123"
  end

  test "invalid recognized units roll back the complete import" do
    ingredient = ingredients(:rolled_oats)
    response = success_response({ foodNutrients: [ { nutrient: { id: 1003, unitName: "mg" }, amount: 9880 } ] })

    assert_no_difference "IngredientNutrientValue.count" do
      assert_raises(Ingredient::FoodDataCentralImport::ImportError) do
        Ingredient::FoodDataCentralImport.new(
          ingredient:, food_id: 123, api_key: "protected-test-key", requester: ->(_uri) { response }
        ).import!
      end
    end
    assert_nil ingredient.reload.food_data_central_id
  end

  private
    def success_response(payload)
      Net::HTTPOK.new("1.1", "200", "OK").tap do |response|
        response.instance_variable_set(:@body, JSON.generate(payload))
        response.instance_variable_set(:@read, true)
      end
    end
end
