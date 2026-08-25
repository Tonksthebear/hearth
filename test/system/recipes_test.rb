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
    assert_selector "h1", text: "Add recipe", wait: 5
    find_field("Title").set("Lemony Chickpea Bowl")
    assert_field "Title", with: "Lemony Chickpea Bowl"
    fill_in_and_wait_for_value "Description", "A bright pantry meal"
    fill_in_and_wait_for_value "Yield", "2 bowls"
    fill_in_and_wait_for_value "Source name", "Household Notebook"
    fill_in_and_wait_for_value "Source URL", "https://example.com/chickpea-bowl"
    select_element_and_wait "Provenance", "Adapted"
    attach_file "Cover image", file_fixture("recipes/cover.png")

    fill_in_and_wait_for_value "Amount", "1"
    fill_in_and_wait_for_value "Unit", "can"
    create_ingredient_option_and_wait "Chickpeas"
    fill_in_and_wait_for_value "Notes", "Drained"
    click_button_and_wait_for_count "Add ingredient", "select[name*='recipe_ingredients_attributes'][name$='[display_name]'] + .ss-main", 2
    assert_selector "input[type='hidden'][name='recipe[cover]']", visible: :hidden
    staged_cover_blob = ActiveStorage::Blob.find_signed!(
      find("input[type='hidden'][name='recipe[cover]']", visible: :hidden).value
    )
    attach_file "Cover image", file_fixture("recipes/replacement-cover.png")
    set_and_wait all("input[name*='recipe_ingredients_attributes'][name$='[display_quantity]']")[1], "1"
    set_and_wait all("input[name*='recipe_ingredients_attributes'][name$='[unit]']")[1], "tbsp"
    create_ingredient_option_and_wait "Lemon juice", index: 1

    fill_in_and_wait_for_value "Step", "Combine the chickpeas and lemon."
    click_button_and_wait_for_count "Add step", "textarea[name*='recipe_instructions_attributes'][name$='[body]']", 2
    set_and_wait all("textarea[name*='recipe_instructions_attributes'][name$='[body]']")[1], "Serve immediately."
    set_and_wait all("input[name*='recipe_instructions_attributes'][name$='[duration_amount]']")[0], "5"
    all("select[name*='recipe_instructions_attributes'][name$='[duration_unit]']")[0].select("Minutes")
    set_and_wait all("input[name*='recipe_instructions_attributes'][name$='[temperature_amount]']")[0], "350"
    all("select[name*='recipe_instructions_attributes'][name$='[temperature_unit]']")[0].select("°F")
    select_instruction_ingredients_and_wait [ "Lemon juice", "Chickpeas" ]

    click_button_and_wait_for_text "Create Recipe", "Lemony Chickpea Bowl"
    assert_selector "h1", text: "Lemony Chickpea Bowl"
    assert_text "Household Notebook"
    assert_text "not clinical endorsement"
    assert_text "does not provide medical advice"
    assert_selector "img[alt='Lemony Chickpea Bowl cover']"
    recipe = Recipe.find_by!(title: "Lemony Chickpea Bowl")
    assert_not_equal staged_cover_blob.id, recipe.cover.blob.id
    instruction = recipe.recipe_instructions.first
    assert_equal %w[Chickpeas Lemon\ juice], instruction.referenced_recipe_ingredients.pluck(:display_name)
    assert_equal [ 1, 2 ], instruction.recipe_instruction_ingredients.pluck(:position)
    assert_text "5 minutes"
    assert_text "350°F"

    click_link_and_wait_for_path "Back to recipes", recipes_path
    fill_in_and_wait_for_value "Search", "Chickpeas"
    select_element_and_wait "Source status", "Adapted"
    click_button_and_wait_for_absence "Filter", "h3", recipes(:porridge).title
    assert_selector "h3", text: "Lemony Chickpea Bowl"
    assert_no_selector "h3", text: recipes(:porridge).title

    click_link_and_wait_for_path "Lemony Chickpea Bowl", recipe_path(Recipe.find_by!(title: "Lemony Chickpea Bowl"))
    assert_text "Household Notebook"
    assert_text "Adapted"

    original_cover_blob = recipe.cover.blob
    removed_ingredient = recipe.recipe_ingredients.find_by!(display_name: "Chickpeas")
    click_link_and_wait_for_path "Edit recipe", edit_recipe_path(recipe)
    fill_in_and_wait_for_value "Title", "Lemony Chickpea Supper"
    click_button_and_wait_for_path "Update Recipe", recipe_path(recipe)
    assert_selector "h1", text: "Lemony Chickpea Supper"
    assert_equal original_cover_blob, recipe.reload.cover.blob

    click_link_and_wait_for_path "Edit recipe", edit_recipe_path(recipe)
    attach_file "Cover image", file_fixture("recipes/replacement-cover.png")
    click_element_and_wait_for_count find("button[name='remove_ingredient'][value='0']"),
      "select[name*='recipe_ingredients_attributes'][name$='[display_name]'] + .ss-main",
      1
    assert_selector "input[name*='recipe_ingredients_attributes'][name$='[_destroy]'][value='1']", visible: :hidden
    click_button_and_wait_for_count "Add ingredient", "select[name*='recipe_ingredients_attributes'][name$='[display_name]'] + .ss-main", 2
    create_ingredient_option_and_wait "Parsley", index: 1
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
    assert_selector "img[alt='Lemony Chickpea Supper cover']"
    assert_field "Remove cover when this recipe is saved", visible: :all

    fill_in_and_wait_for_value "Source name", ""
    attach_file "Cover image", file_fixture("recipes/cover.png")
    click_button_and_wait_for_text "Update Recipe", "Source name can't be blank"
    staged_replacement_blob = ActiveStorage::Blob.find_signed!(
      find("input[type='hidden'][name='recipe[cover]']", visible: :hidden).value
    )
    fill_in_and_wait_for_value "Source name", "Household Notebook"
    check_and_wait find_field("Remove cover when this recipe is saved", visible: :all)
    click_button_and_wait_for_path "Update Recipe", recipe_path(recipe)
    assert_selector "[role='img'][aria-label='No cover image for Lemony Chickpea Supper']"
    assert_not recipe.reload.cover.attached?
    assert_not ActiveStorage::Blob.exists?(replacement_blob.id)
    assert_not ActiveStorage::Blob.exists?(staged_replacement_blob.id)
  end

  test "edits manual ingredient nutrition while preserving known zero" do
    sign_in_via_browser users(:one)
    visit recipes_path
    click_link_and_wait_for_path "Ingredient nutrition", ingredients_path

    find("tr", text: ingredients(:lettuce).name).find_link("Edit").click
    assert_current_path edit_ingredient_path(ingredients(:lettuce)), wait: 5
    assert_no_selector "html[aria-busy='true']"
    fill_in_and_wait_for_value "Protein (g)", "10.5"
    fill_in_and_wait_for_value "Energy (kcal)", "0"
    select_element_and_wait "Provenance", "Personal"
    fill_in_and_wait_for_value "Source name", ""
    click_button_and_wait_for_path "Save nutrition", ingredients_path

    within "tr", text: ingredients(:lettuce).name do
      assert_text "10.5 g"
      assert_text "0 kcal"
    end
  end

  private
    def create_ingredient_option_and_wait(value, index: 0)
      label = all("label", text: "Ingredient", exact_text: true)[index]
      select = find_by_id(label[:for], visible: :all)
      slim_select = select.sibling(".ss-main")
      slim_select.click
      content = find(".ss-content[data-id='#{slim_select['data-id']}']", visible: :visible, wait: 5)
      within content do
        search = find("input[type='search']", visible: :visible)
        search.send_keys(value)
        search.send_keys(:enter)
      end
      assert_selector "option:checked", text: value, visible: :all, wait: 5
      assert_equal value, select.find("option:checked", visible: :all).text
    end

    def select_instruction_ingredients_and_wait(values)
      label = all("label", text: "Referenced ingredients", exact_text: true).first
      select = find_by_id(label[:for], visible: :all)
      slim_select = select.sibling(".ss-main")

      values.each do |value|
        slim_select.click unless slim_select["aria-expanded"] == "true"
        content = find(".ss-content[data-id='#{slim_select['data-id']}']", visible: :visible, wait: 5)
        within content do
          search = find("input[type='search']", visible: :visible)
          search.set("")
          search.send_keys(value)
          assert_selector ".ss-option", text: value, exact_text: true, count: 1, wait: 5
          find(".ss-option", text: value, exact_text: true).click
        end

        assert_selector "option:checked", text: value, visible: :all, wait: 5
        slim_select.click
        assert_equal "false", slim_select["aria-expanded"]
      end

      assert_equal values.sort, select.all("option:checked", visible: :all).map(&:text).sort
    end
end
