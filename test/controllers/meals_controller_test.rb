require "test_helper"

class MealsControllerTest < ActionDispatch::IntegrationTest
  test "new renders one directly typeable free text item" do
    sign_in_as users(:one)

    get new_meal_path(date: "2026-07-31")

    assert_response :success
    assert_select "input[name='meal[eaten_on]'][value='2026-07-31']"
    assert_select "input[name*='meal_items_attributes'][name$='[source_kind]'][value='free_text']", count: 1
    assert_select "input[name*='meal_items_attributes'][name$='[snapshot_label]'][autofocus]", count: 1
    assert_select "button[name='remove_item']", count: 1
    assert_select "#meal_form form.mt-8.space-y-12"
    assert_select "ul[role='list'].divide-y"
    assert_select "button[formnovalidate][name='add_recipe_item']"
    assert_select "button[name='move_item']", count: 0
    assert_select "input[name*='meal_items_attributes'][name$='[position]']", count: 0
  end


  test "visible recipe item form prefills one editable serving" do
    sign_in_as users(:one)

    post meals_path,
      params: { meal: { eaten_on: "2026-07-31", meal_items_attributes: { "0" => { source_kind: "free_text", snapshot_label: "Soup" } } }, add_recipe_item: "1" },
      headers: turbo_stream_headers

    assert_response :success
    assert_select "li[data-meal-item-kind='recipe'] input[name$='[portion_amount]'][value='1']"
    assert_select "li[data-meal-item-kind='recipe'] input[name$='[portion_unit]'][value='servings']"
  end

  test "show renders historical snapshot amounts and completeness" do
    sign_in_as users(:one)

    get meal_path(meals(:alex_recipe_target_week))

    assert_response :success
    assert_select "#meal-nutrition-heading", text: "Nutrition snapshot"
    assert_select "section", text: /Protein.*9\.26 g/m
    assert_select "span", text: /Nutrition status:.*estimated/i
  end

  test "invalid form uses the shared alert and Elements aria-invalid state" do
    sign_in_as users(:one)

    post meals_path, params: { meal: { eaten_on: "", meal_items_attributes: {
      "0" => { source_kind: "free_text", snapshot_label: "" }
    } } }

    assert_response :unprocessable_entity
    assert_select "#meal-errors[role='alert']"
    assert_select "input[name='meal[eaten_on]'][aria-invalid='true']"
    assert_select "input[name$='[snapshot_label]'][aria-invalid='true']"
  end

  test "creates a Current person meal from actual nested HTML-shaped params" do
    sign_in_as users(:one)

    assert_difference [ "Meal.count", "MealItem.count" ], 1 do
      post meals_path, params: { meal: {
        eaten_on: "2026-07-31", person_id: people(:two).id, notes: "Late lunch",
        meal_items_attributes: {
          "0" => { source_kind: "recipe", recipe_id: recipes(:porridge).id, portion_amount: "1.5", portion_unit: "servings" }
        }
      } }
    end

    meal = Meal.order(:created_at).last
    assert_equal people(:one), meal.person
    assert_equal recipes(:porridge), meal.meal_items.first.recipe
    assert_equal "Late lunch", meal.notes
    assert_redirected_to meal_path(meal)
  end

  test "creates a multi-component meal without catalog mutation" do
    sign_in_as users(:one)

    assert_difference "MealItem.count", 3 do
      assert_no_difference [ "Recipe.count", "Ingredient.count" ] do
        post meals_path, params: { meal: { eaten_on: "2026-07-31", meal_items_attributes: {
          "0" => { source_kind: "recipe", recipe_id: recipes(:porridge).id },
          "1" => { source_kind: "ingredient", ingredient_id: ingredients(:rolled_oats).id },
          "2" => { source_kind: "free_text", snapshot_label: "Airport sandwich" }
        } } }
      end
    end

    assert_response :see_other
    assert_equal [ 1, 2, 3 ], Meal.order(:created_at).last.meal_items.map(&:position)
  end

  test "Turbo add and remove replace the full unsaved form with values preserved" do
    sign_in_as users(:one)
    params = { meal: { eaten_on: "2026-07-31", notes: "Preserve me", meal_items_attributes: {
      "0" => { source_kind: "free_text", snapshot_label: "Soup" }
    } } }

    post meals_path, params: params.merge(add_recipe_item: "1"), headers: turbo_stream_headers

    assert_response :success
    assert_select "turbo-stream[action='replace'][target='meal_form']"
    assert_select "textarea[name='meal[notes]']", text: "Preserve me"
    assert_select "input[name$='[snapshot_label]'][value='Soup']"
    assert_select "input[name$='[source_kind]'][value='recipe']"
    assert_select "textarea[name*='recipe_feedback_attributes'][name$='[body]']", count: 1
  end

  test "new meal keeps recipe feedback available across structural and invalid rerenders" do
    sign_in_as users(:one)
    attributes = { meal: { eaten_on: "2026-07-31", meal_items_attributes: {
      "0" => {
        source_kind: "recipe", recipe_id: recipes(:porridge).id,
        recipe_feedback_attributes: { body: "" }
      }
    } } }

    post meals_path, params: attributes.merge(add_free_text_item: "1"), headers: turbo_stream_headers

    assert_response :success
    assert_select "textarea[name*='recipe_feedback_attributes'][name$='[body]']", count: 1
    assert_select "li[data-meal-item-kind]", count: 2

    attributes[:meal][:eaten_on] = ""
    post meals_path, params: attributes

    assert_response :unprocessable_entity
    assert_select "#meal-errors[role='alert']"
    assert_select "textarea[name*='recipe_feedback_attributes'][name$='[body]']", count: 1
  end

  test "rejects foreign household sources and forged nested ids" do
    sign_in_as users(:one)
    foreign_recipe = create_foreign_recipe

    assert_no_difference "Meal.count" do
      post meals_path, params: { meal: { eaten_on: "2026-07-31", meal_items_attributes: {
        "0" => { source_kind: "recipe", recipe_id: foreign_recipe.id }
      } } }
    end
    assert_response :unprocessable_entity

    patch meal_path(meals(:alex_recipe_target_week)), params: { meal: { eaten_on: "2026-07-27", meal_items_attributes: {
      "0" => { id: meal_items(:sam_soup).id, source_kind: "recipe", recipe_id: recipes(:salad).id }
    } } }
    assert_response :not_found
  end

  test "show is household-readable while edit update and destroy remain owner-scoped" do
    sign_in_as users(:one)
    other = meals(:sam_recipe_target_week)

    get meal_path(other)
    assert_response :success
    assert_select "h1", text: other.description
    assert_select "article", text: /#{Regexp.escape(other.person.name)}/
    assert_select "a", text: "Edit meal", count: 0
    assert_select "form[action='#{meal_path(other)}']", count: 0

    get edit_meal_path(other)
    assert_response :not_found

    patch meal_path(other), params: { meal: { notes: "Forged change" } }
    assert_response :not_found
    assert_not_equal "Forged change", other.reload.notes

    assert_no_difference "Meal.count" do
      delete meal_path(other)
    end
    assert_response :not_found

    get meal_path(meals(:alex_recipe_target_week))
    assert_response :success
    assert_select "a", text: "Edit meal", count: 1
    assert_select "form[action='#{meal_path(meals(:alex_recipe_target_week))}']", count: 1
  end

  test "other household meal training catalog and shopping records are not exposed" do
    sign_in_as users(:one)
    foreign_recipe = create_foreign_recipe
    foreign_household = foreign_recipe.household
    foreign_person = foreign_household.people.create!(name: "Foreign person")
    foreign_meal = foreign_person.meals.create!(
      household: foreign_household,
      eaten_on: Date.new(2026, 7, 31),
      meal_items_attributes: [ { source_kind: :recipe, recipe: foreign_recipe } ]
    )
    foreign_session = foreign_person.training_sessions.create!(
      household: foreign_household,
      snapshot_title: "Foreign workout",
      performed_on: Date.new(2026, 7, 31),
      started_at: Time.zone.local(2026, 7, 31, 8)
    )
    foreign_item = foreign_household.shopping_lists
      .create!(week_start: Date.new(2026, 7, 27))
      .items.create!(name: "Foreign groceries", user_managed_at: Time.current)

    get meal_path(foreign_meal)
    assert_response :not_found

    get recipe_path(foreign_recipe)
    assert_response :not_found

    get training_session_path(foreign_session)
    assert_response :not_found

    get edit_shopping_list_item_path(foreign_item)
    assert_response :not_found

    assert_no_changes -> { foreign_item.reload.completed_at } do
      post shopping_list_item_completion_path(foreign_item)
    end
    assert_response :not_found
  end

  test "clearing persisted recipe feedback removes feedback without removing the meal item" do
    sign_in_as users(:one)
    item = meal_items(:alex_salad)
    feedback = recipe_feedbacks(:alex_salad_feedback)

    assert_difference "RecipeFeedback.count", -1 do
      assert_no_difference "MealItem.count" do
        patch meal_path(item.meal), params: { meal: {
          eaten_on: item.meal.eaten_on,
          meal_items_attributes: {
            "0" => {
              id: item.id, source_kind: "recipe", recipe_id: item.recipe_id,
              recipe_feedback_attributes: { id: feedback.id, body: "" }
            }
          }
        } }
      end
    end

    assert_redirected_to meal_path(item.meal)
    assert_nil item.reload.recipe_feedback
  end

  private
    def turbo_stream_headers
      { "Accept" => Mime[:turbo_stream].to_s }
    end

    def create_foreign_recipe
      connection = ActiveRecord::Base.connection
      connection.execute("PRAGMA ignore_check_constraints = ON")
      household_id = Household.insert_all!([ {
        name: "Impossible second installation", installation_key: 2,
        created_at: Time.current, updated_at: Time.current
      } ], returning: %w[id]).rows.first.first
      recipe_id = Recipe.insert_all!([ {
        household_id: household_id, title: "Foreign recipe", provenance_status: "personal",
        created_at: Time.current, updated_at: Time.current
      } ], returning: %w[id]).rows.first.first
      Recipe.find(recipe_id)
    ensure
      connection&.execute("PRAGMA ignore_check_constraints = OFF")
    end
end
