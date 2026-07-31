require "application_system_test_case"

class RecipesTest < ApplicationSystemTestCase
  test "household maintains searches and edits an attributed recipe" do
    visit new_session_path
    fill_in "Email address", with: users(:one).email_address
    fill_in "Password", with: "password"
    click_button_and_wait_for_path "Sign in", root_path

    click_link_and_wait_for_path "Meals", meal_week_path
    click_link_and_wait_for_path "Recipes", recipes_path
    assert_selector "section[aria-labelledby='recipes-heading'] h1", text: "Recipes"
    assert_text "does not provide medical advice"

    click_link_and_wait_for_path "Add recipe", new_recipe_path
    fill_in_and_wait_for_value "Title", "Lemony Chickpea Bowl"
    fill_in_and_wait_for_value "Description", "A bright pantry meal"
    fill_in_and_wait_for_value "Yield", "2 bowls"
    fill_in_and_wait_for_value "Source name", "Household Notebook"
    fill_in_and_wait_for_value "Source URL", "https://example.com/chickpea-bowl"
    select_element_and_wait "Provenance", "Adapted"
    attach_file "Cover image", file_fixture("recipes/cover.png")

    fill_in_and_wait_for_value "Amount", "1"
    fill_in_and_wait_for_value "Unit", "can"
    fill_in_and_wait_for_value "Name", "Chickpeas"
    fill_in_and_wait_for_value "Notes", "Drained"
    click_button_and_wait_for_count "Add ingredient", "input[name*='recipe_ingredients_attributes'][name$='[name]']", 2
    assert_selector "input[type='hidden'][name='recipe[cover]']", visible: :hidden
    staged_cover_blob = ActiveStorage::Blob.find_signed!(
      find("input[type='hidden'][name='recipe[cover]']", visible: :hidden).value
    )
    attach_file "Cover image", file_fixture("recipes/replacement-cover.png")
    set_and_wait all("input[name*='recipe_ingredients_attributes'][name$='[amount]']")[1], "1"
    set_and_wait all("input[name*='recipe_ingredients_attributes'][name$='[unit]']")[1], "tbsp"
    set_and_wait all("input[name*='recipe_ingredients_attributes'][name$='[name]']")[1], "Lemon juice"

    fill_in_and_wait_for_value "Step", "Combine the chickpeas and lemon."
    click_button_and_wait_for_count "Add step", "textarea[name*='recipe_instructions_attributes'][name$='[body]']", 2
    set_and_wait all("textarea[name*='recipe_instructions_attributes'][name$='[body]']")[1], "Serve immediately."

    click_button_and_wait_for_text "Create Recipe", "Lemony Chickpea Bowl"
    assert_selector "h1", text: "Lemony Chickpea Bowl"
    assert_text "Household Notebook"
    assert_text "not clinical endorsement"
    assert_text "does not provide medical advice"
    assert_selector "img[alt='Lemony Chickpea Bowl cover']"
    recipe = Recipe.find_by!(title: "Lemony Chickpea Bowl")
    assert_not_equal staged_cover_blob.id, recipe.cover.blob.id

    click_link_and_wait_for_path "Back to recipes", recipes_path
    fill_in_and_wait_for_value "Search", "Chickpeas"
    select_element_and_wait "Provenance", "Adapted"
    click_button_and_wait_for_absence "Filter", "h2", recipes(:porridge).title
    assert_selector "h2", text: "Lemony Chickpea Bowl"
    assert_no_selector "h2", text: recipes(:porridge).title

    click_link_and_wait_for_path "Lemony Chickpea Bowl", recipe_path(Recipe.find_by!(title: "Lemony Chickpea Bowl"))
    assert_text "Household Notebook"
    assert_text "Adapted"

    original_cover_blob = recipe.cover.blob
    removed_ingredient = recipe.recipe_ingredients.find_by!(name: "Chickpeas")
    click_link_and_wait_for_path "Edit recipe", edit_recipe_path(recipe)
    fill_in_and_wait_for_value "Title", "Lemony Chickpea Supper"
    click_button_and_wait_for_path "Update Recipe", recipe_path(recipe)
    assert_selector "h1", text: "Lemony Chickpea Supper"
    assert_equal original_cover_blob, recipe.reload.cover.blob

    click_link_and_wait_for_path "Edit recipe", edit_recipe_path(recipe)
    attach_file "Cover image", file_fixture("recipes/replacement-cover.png")
    click_element_and_wait_for_count find("button[name='remove_ingredient'][value='0']"),
      "input[name*='recipe_ingredients_attributes'][name$='[name]']",
      1
    assert_selector "input[name*='recipe_ingredients_attributes'][name$='[_destroy]'][value='1']", visible: :hidden
    click_button_and_wait_for_count "Add ingredient", "input[name*='recipe_ingredients_attributes'][name$='[name]']", 2
    set_and_wait all("input[name*='recipe_ingredients_attributes'][name$='[name]']")[1], "Parsley"
    click_button_and_wait_for_path "Update Recipe", recipe_path(recipe)

    visit recipe_path(recipe)
    assert_selector "img[alt='Lemony Chickpea Supper cover']"
    assert_not_equal original_cover_blob.id, recipe.reload.cover.blob.id
    assert_not ActiveStorage::Blob.exists?(original_cover_blob.id)
    assert_no_text "Chickpeas"
    assert_text "Lemon juice"
    assert_text "Parsley"
    assert_not RecipeIngredient.exists?(removed_ingredient.id)
    assert_equal [ 1, 2 ], recipe.reload.recipe_ingredients.pluck(:position)

    replacement_blob = recipe.cover.blob
    click_link_and_wait_for_path "Edit recipe", edit_recipe_path(recipe)
    attach_file "Cover image", file_fixture("recipes/not-an-image.txt")
    click_button_and_wait_for_text "Update Recipe", "Cover must be a JPEG, PNG, or GIF"
    assert_equal replacement_blob, recipe.reload.cover.blob

    visit_and_wait_for_path edit_recipe_path(recipe)
    check_and_wait find_field("Remove cover when this recipe is saved", visible: :all)
    click_button_and_wait_for_path "Update Recipe", recipe_path(recipe)
    assert_selector "[role='img'][aria-label='No cover image for Lemony Chickpea Supper']"
    assert_not recipe.reload.cover.attached?
    assert_not ActiveStorage::Blob.exists?(replacement_blob.id)
  end
end
