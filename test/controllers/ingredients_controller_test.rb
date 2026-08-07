require "test_helper"

class IngredientsControllerTest < ActionDispatch::IntegrationTest
  test "index and edit enter through the household recipe catalog" do
    sign_in_as users(:one)

    get recipes_path
    assert_select "a[href='#{ingredients_path}']", text: "Ingredient nutrition"

    get ingredients_path
    assert_response :success
    assert_select "nav[aria-label='Primary'] a[aria-current='page']", text: "Meals"
    assert_select "nav[aria-label='Meals'] a[aria-current='page']", text: "Recipes"
    assert_select "table[data-nutrition-table]", text: /Lettuce.*Complete/m
    assert_select "table[data-nutrition-table]", text: /Carrots.*No values/m
    assert_select "a[href='#{edit_ingredient_path(ingredients(:lettuce))}']", text: "Edit"

    get ingredients_path, params: { q: "blue" }
    assert_response :success
    assert_select "tr", text: /Blueberries/
    assert_select "tr", text: /Lettuce/, count: 0

    get edit_ingredient_path(ingredients(:lettuce))
    assert_response :success
    assert_select "input[name*='ingredient_nutrient_values_attributes'][name$='[amount_per_100_grams]']", count: 6
    assert_select "input[value='0.0']", minimum: 1
  end

  test "update preserves known zero and deletes a cleared value" do
    sign_in_as users(:one)
    ingredient = ingredients(:lettuce)
    protein = ingredient_nutrient_values(:lettuce_protein)
    energy = ingredient_nutrient_values(:lettuce_energy)

    patch ingredient_path(ingredient), params: { ingredient: {
      nutrition_provenance_status: "personal",
      nutrition_source_name: "",
      ingredient_nutrient_values_attributes: {
        "0" => { id: energy.id, nutrient_id: nutrients(:energy).id, amount_per_100_grams: "0" },
        "1" => { id: protein.id, nutrient_id: nutrients(:protein).id, amount_per_100_grams: "" }
      }
    } }

    assert_redirected_to ingredients_path
    assert_equal BigDecimal("0"), energy.reload.amount_per_100_grams
    assert_not IngredientNutrientValue.exists?(protein.id)
  end

  test "foreign household ingredient ids are not available" do
    sign_in_as users(:one)
    foreign = Ingredient.new(id: 0)

    get edit_ingredient_path(foreign)
    assert_response :not_found
    patch ingredient_path(foreign), params: { ingredient: { nutrition_provenance_status: "personal" } }
    assert_response :not_found
  end
end
