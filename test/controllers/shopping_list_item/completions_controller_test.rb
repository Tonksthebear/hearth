require "test_helper"

class ShoppingListItem::CompletionsControllerTest < ActionDispatch::IntegrationTest
  test "check and uncheck mutate only the targeted household item" do
    sign_in_as users(:one)
    item = shopping_list_items(:manual_milk)
    other = shopping_list_items(:completed_foil)
    other_completed_at = other.completed_at

    post shopping_list_item_completion_path(item)
    assert item.reload.completed?
    assert_equal other_completed_at, other.reload.completed_at

    delete shopping_list_item_completion_path(item)
    refute item.reload.completed?
    assert_equal other_completed_at, other.reload.completed_at
  end

  test "unknown and anonymous completion requests cannot mutate items" do
    sign_in_as users(:one)
    assert_no_changes -> { shopping_list_items(:manual_milk).reload.completed_at } do
      post shopping_list_item_completion_path(0)
    end
    assert_response :not_found

    delete session_path
    post shopping_list_item_completion_path(shopping_list_items(:manual_milk))
    assert_redirected_to new_session_path
  end
end
