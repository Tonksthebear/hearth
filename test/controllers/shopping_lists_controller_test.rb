require "test_helper"

class ShoppingListsControllerTest < ActionDispatch::IntegrationTest
  test "normal explicit visit reconciles the household week into aggregated deficits with their source state" do
    sign_in_as users(:one)

    get shopping_list_path, params: { date: "2026-07-27" }

    assert_response :success
    # Both salad plans are short one head of lettuce against an `out` pantry row,
    # so they aggregate into one deficit with two contributing meals. The
    # substituted soup requirement is still unresolved and produces no row.
    assert_select "#shopping-list li[data-completed]", 3
    assert_select "#shopping-list", text: /2 head\s+Lettuce/
    assert_select "#shopping-list", text: /Carrots/, count: 0
    assert_select "el-disclosure", minimum: 1
    assert_select "[data-confirmation-state='on_hand']", text: "On hand"
    assert_select "[data-confirmation-state='pantry_evidence']", text: "From pantry evidence"

    lettuce = ShoppingListItem.find_by!(shopping_list: shopping_lists(:target_week), name: "Lettuce")
    assert_equal [ planned_meal_ingredients(:shared_salad_lettuce), planned_meal_ingredients(:sam_salad_lettuce) ],
      lettuce.planned_meal_ingredients.to_a
    assert_select "a[href=?]", new_shopping_list_item_pantry_confirmation_path(lettuce), text: "Confirm purchase"
  end

  test "the deficit list states that checking an item off claims no pantry inventory" do
    sign_in_as users(:one)

    get shopping_list_path, params: { date: "2026-07-27" }

    assert_response :success
    assert_select "p", text: /never claims pantry inventory/
  end

  test "prefetch shaped visit does not create reconcile or touch persisted shopping state" do
    sign_in_as users(:one)
    date = Date.new(2026, 10, 5)
    before = [ ShoppingList.count, ShoppingListItem.count, ShoppingListItemSource.count ]

    get shopping_list_path, params: { date: date.iso8601 }, headers: { "X-Sec-Purpose" => "prefetch" }

    assert_response :no_content
    assert_equal before, [ ShoppingList.count, ShoppingListItem.count, ShoppingListItemSource.count ]

    get shopping_list_path, params: { date: date.iso8601 }
    assert_response :success
    assert ShoppingList.exists?(household: households(:home), week_start: date)
  end

  test "invalid date safely renders the current household shopping week" do
    sign_in_as users(:one)

    travel_to Date.new(2026, 7, 27) do
      get shopping_list_path, params: { date: "not-a-date" }

      assert_response :success
      assert_select "p", text: /July 27, 2026/
    end
  end

  test "anonymous visit redirects to sign in" do
    get shopping_list_path

    assert_redirected_to new_session_path
  end

  test "contributing meals keep named provenance and explain reserved vs short ownership" do
    sign_in_as users(:one)

    get shopping_list_path, params: { date: "2026-07-27" }

    assert_response :success
    lettuce = ShoppingListItem.find_by!(shopping_list: shopping_lists(:target_week), name: "Lettuce")
    assert_equal 2, lettuce.shopping_list_item_sources.size
    assert_select "#shopping-list-item-#{lettuce.id} [data-shopping-ownership]", count: 2
    lettuce.planned_meals.each do |planned_meal|
      assert_select "#shopping-list-item-#{lettuce.id} [data-source-plan=?]", planned_meal.id.to_s, text: /#{Regexp.escape(planned_meal.recipe.title)}/
    end
    assert_select "#shopping-list-item-#{lettuce.id} [data-ownership-role='short']", count: 2
    assert_select "#shopping-list-item-#{lettuce.id} [data-confirmation-state='on_hand']", text: "On hand"
    assert_select "#shopping-list-item-#{lettuce.id} [data-confirmation-state='pantry_evidence']", text: "From pantry evidence"
  end

  test "ownership lines stay unit-scoped and do not replace an unmeasurable source meal" do
    sign_in_as users(:one)
    week_start = Date.new(2026, 9, 7)
    flour = Ingredient.resolve!(household: households(:home), name: "Flour")
    basil = Ingredient.resolve!(household: households(:home), name: "Basil")
    PantryItem.for(household: households(:home), ingredient: flour).mark_out!(
      source: "pantry_check", confirmed_by: people(:without_login)
    )
    PantryItem.for(household: households(:home), ingredient: basil).mark_out!(
      source: "pantry_check", confirmed_by: people(:without_login)
    )

    bread = households(:home).recipes.create!(
      title: "Bread", source_name: "Test", provenance_status: :observed,
      recipe_ingredients_attributes: [ { display_name: "Flour", display_quantity: "200", unit: "g", position: 1 } ]
    )
    cake = households(:home).recipes.create!(
      title: "Cake", source_name: "Test", provenance_status: :observed,
      recipe_ingredients_attributes: [ { display_name: "Flour", display_quantity: "2", unit: "cup", position: 1 } ]
    )
    handful = households(:home).recipes.create!(
      title: "Handful salad", source_name: "Test", provenance_status: :observed,
      recipe_ingredients_attributes: [ { display_name: "Basil", display_quantity: "a handful", unit: nil, position: 1 } ]
    )
    pesto = households(:home).recipes.create!(
      title: "Pesto", source_name: "Test", provenance_status: :observed,
      recipe_ingredients_attributes: [ { display_name: "Basil", display_quantity: "50", unit: "g", position: 1 } ]
    )

    plans = [ bread, cake, handful, pesto ].map.with_index do |recipe, index|
      plan = households(:home).planned_meals.create!(recipe:, planned_on: week_start + index.days)
      plan.planned_meal_ingredients.active.each { |requirement| requirement.decide!(:missing) }
      plan
    end
    bread_plan, cake_plan, handful_plan, pesto_plan = plans

    get shopping_list_path, params: { date: week_start.iso8601 }

    assert_response :success
    flour_g = ShoppingListItem.find_by!(name: "Flour", unit: "g")
    flour_cup = ShoppingListItem.find_by!(name: "Flour", unit: "cup")
    basil_handful = ShoppingListItem.where(name: "Basil").find { |item| item.unit.blank? }
    basil_g = ShoppingListItem.find_by!(name: "Basil", unit: "g")

    assert_equal [ bread_plan.id ], flour_g.planned_meals.ids
    assert_equal [ cake_plan.id ], flour_cup.planned_meals.ids
    assert_equal [ handful_plan.id ], basil_handful.planned_meals.ids
    assert_equal [ pesto_plan.id ], basil_g.planned_meals.ids

    assert_select "#shopping-list-item-#{flour_g.id} [data-shopping-ownership]", count: 1
    assert_select "#shopping-list-item-#{flour_g.id}", text: /Bread/
    assert_select "#shopping-list-item-#{flour_g.id}", text: /Cake/, count: 0

    assert_select "#shopping-list-item-#{flour_cup.id} [data-shopping-ownership]", count: 1
    assert_select "#shopping-list-item-#{flour_cup.id}", text: /Cake/
    assert_select "#shopping-list-item-#{flour_cup.id}", text: /Bread/, count: 0

    assert_select "#shopping-list-item-#{basil_handful.id} [data-shopping-ownership]", count: 1
    assert_select "#shopping-list-item-#{basil_handful.id}", text: /Handful salad/
    assert_select "#shopping-list-item-#{basil_handful.id}", text: /Pesto/, count: 0
    assert_select "#shopping-list-item-#{basil_handful.id} [data-confirmation-state]", minimum: 1
  end
end
