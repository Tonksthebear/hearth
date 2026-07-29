require "application_system_test_case"

class RecipesTest < ApplicationSystemTestCase
  test "household maintains searches and edits an attributed recipe" do
    visit new_session_path
    fill_in "Email address", with: users(:one).email_address
    fill_in "Password", with: "password"
    click_button_and_wait_for_path "Sign in", root_path

    click_link_and_wait_for_path "Recipes", recipes_path
    assert_selector "section[aria-labelledby='recipes-heading'] h1", text: "Recipes"
    assert_text "does not provide medical advice"

    click_link_and_wait_for_path "Add recipe", new_recipe_path
    fill_in_and_wait_for_value "Title", "Lemony Chickpea Bowl"
    fill_in_and_wait_for_value "Description", "A bright pantry meal"
    fill_in_and_wait_for_value "Yield", "2 bowls"
    fill_in_and_wait_for_value "Source name", "Household Notebook"
    fill_in_and_wait_for_value "Source URL", "https://example.com/chickpea-bowl"
    select "Adapted", from: "Provenance"

    fill_in_and_wait_for_value "Amount", "1"
    fill_in_and_wait_for_value "Unit", "can"
    fill_in_and_wait_for_value "Name", "Chickpeas"
    fill_in_and_wait_for_value "Notes", "Drained"
    click_button_and_wait_for_count "Add ingredient", "input[name*='recipe_ingredients_attributes'][name$='[name]']", 2
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

    click_link_and_wait_for_path "Back to recipes", recipes_path
    fill_in_and_wait_for_value "Search", "Chickpeas"
    select "Adapted", from: "Provenance"
    click_button_and_wait_for_absence "Filter", "h2", recipes(:porridge).title
    assert_selector "h2", text: "Lemony Chickpea Bowl"
    assert_no_selector "h2", text: recipes(:porridge).title

    click_link_and_wait_for_path "Lemony Chickpea Bowl", recipe_path(Recipe.find_by!(title: "Lemony Chickpea Bowl"))
    assert_text "Household Notebook"
    assert_text "Adapted"

    recipe = Recipe.find_by!(title: "Lemony Chickpea Bowl")
    removed_ingredient = recipe.recipe_ingredients.find_by!(name: "Chickpeas")
    click_link_and_wait_for_path "Edit recipe", edit_recipe_path(recipe)
    click_element_and_wait_for_count find("button[name='remove_ingredient'][value='0']"),
      "input[name*='recipe_ingredients_attributes'][name$='[name]']",
      1
    assert_selector "input[name*='recipe_ingredients_attributes'][name$='[_destroy]'][value='1']", visible: :hidden
    click_button_and_wait_for_path "Update Recipe", recipe_path(recipe)

    visit recipe_path(recipe)
    assert_no_text "Chickpeas"
    assert_text "Lemon juice"
    assert_not RecipeIngredient.exists?(removed_ingredient.id)
  end

  private
    def click_link_and_wait_for_path(label, path)
      link = find_link(label)
      link.click
      execute_script("arguments[0].click()", link) unless page.has_current_path?(path, wait: 5)
      assert_current_path path
    end

    def click_button_and_wait_for_path(label, path)
      button = find_button(label)
      button.click
      execute_script("arguments[0].click()", button) unless page.has_current_path?(path, wait: 5)
      assert_current_path path
    end

    def click_button_and_wait_for_count(label, selector, count)
      click_element_and_wait_for_count find_button(label), selector, count
    end

    def click_element_and_wait_for_count(element, selector, count)
      element.click
      execute_script("arguments[0].click()", element) unless page.has_selector?(selector, count: count, wait: 5)
      assert_selector selector, count: count
    end

    def click_button_and_wait_for_text(label, text)
      button = find_button(label)
      button.click
      execute_script("arguments[0].click()", button) unless page.has_text?(text, wait: 5)
      assert_text text
    end

    def click_button_and_wait_for_absence(label, selector, text)
      button = find_button(label)
      button.click
      execute_script("arguments[0].click()", button) if page.has_selector?(selector, text: text, wait: 5)
      assert_no_selector selector, text: text
    end

    def fill_in_and_wait_for_value(label, value)
      set_and_wait find_field(label), value
    end

    def set_and_wait(field, value)
      field.set(value)
      return if field.value == value

      execute_script(<<~JAVASCRIPT, field, value)
        arguments[0].value = arguments[1];
        arguments[0].dispatchEvent(new Event("input", { bubbles: true }));
        arguments[0].dispatchEvent(new Event("change", { bubbles: true }));
      JAVASCRIPT
      assert_equal value, field.value
    end
end
