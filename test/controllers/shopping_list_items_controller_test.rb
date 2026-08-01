require "test_helper"

class ShoppingListItemsControllerTest < ActionDispatch::IntegrationTest
  test "manual create edit and delete stay scoped to the current household list" do
    sign_in_as users(:one)
    list = shopping_lists(:target_week)

    assert_difference "list.items.count", 1 do
      post shopping_list_items_path, params: {
        date: list.week_start.iso8601,
        shopping_list_item: { name: "Coffee", quantity: "2", unit: "bags", notes: "Whole bean" }
      }
    end
    item = list.items.find_by!(name: "Coffee")
    assert item.user_managed?
    assert_redirected_to shopping_list_path(date: list.week_start)

    get edit_shopping_list_item_path(item)
    assert_response :success
    assert_select "form[action=?]", shopping_list_item_path(item)

    patch shopping_list_item_path(item), params: {
      shopping_list_item: { name: "Coffee beans", quantity: "3", unit: "bags", notes: "Dark roast" }
    }
    assert_equal [ "Coffee beans", "3", "bags", "Dark roast" ], item.reload.values_at(:name, :quantity, :unit, :notes)

    assert_difference "ShoppingListItem.count", -1 do
      delete shopping_list_item_path(item)
    end
  end

  test "required name error renders the real shopping entry page" do
    sign_in_as users(:one)

    assert_no_difference "ShoppingListItem.count" do
      post shopping_list_items_path, params: {
        date: shopping_lists(:target_week).week_start.iso8601,
        shopping_list_item: { name: "", quantity: "1", unit: "box", notes: "" }
      }
    end

    assert_response :unprocessable_entity
    assert_select "#shopping-list-item-errors", text: /Name can't be blank/
    assert_select "h1", text: "Shopping list"
  end

  test "unknown item id is not found without mutation" do
    sign_in_as users(:one)

    assert_no_difference "ShoppingListItem.count" do
      patch shopping_list_item_path(0), params: { shopping_list_item: { name: "Nope" } }
    end
    assert_response :not_found
  end

  test "invalid list date is not found without mutation" do
    sign_in_as users(:one)

    assert_no_difference "ShoppingListItem.count" do
      post shopping_list_items_path, params: {
        date: "not-a-date",
        shopping_list_item: { name: "Nope" }
      }
    end
    assert_response :not_found
  end

  test "generated requirements cannot be deleted through the manual item endpoint" do
    sign_in_as users(:one)
    generated = ShoppingList.for(household: households(:home), date: "2026-07-27").items.find_by!(name: "Carrots")

    assert_no_difference "ShoppingListItem.count" do
      delete shopping_list_item_path(generated)
    end
    assert_response :not_found
  end

  test "anonymous mutations redirect to sign in" do
    post shopping_list_items_path, params: {
      date: shopping_lists(:target_week).week_start.iso8601,
      shopping_list_item: { name: "Nope" }
    }

    assert_redirected_to new_session_path
  end
end
