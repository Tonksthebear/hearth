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
end
