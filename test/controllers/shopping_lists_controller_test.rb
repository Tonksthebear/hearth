require "test_helper"

class ShoppingListsControllerTest < ActionDispatch::IntegrationTest
  test "normal explicit visit reconciles the household week and renders persisted provenance" do
    sign_in_as users(:one)

    get shopping_list_path, params: { date: "2026-07-27" }

    assert_response :success
    assert_select "#shopping-list li[data-completed]", minimum: 4
    assert_select "#shopping-list", text: /Carrots/
    assert_select "#shopping-list", text: /Lettuce/
    assert_select "el-disclosure", minimum: 1
    assert ShoppingListItemSource.exists?
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
