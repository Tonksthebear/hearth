require "test_helper"

class ShoppingListItemTest < ActiveSupport::TestCase
  test "completion timestamps change only through explicit completion methods" do
    item = shopping_list_items(:manual_milk)

    item.complete!
    completed_at = item.completed_at
    assert completed_at
    item.complete!
    assert_equal completed_at, item.completed_at

    item.uncomplete!
    assert_nil item.completed_at
  end
end
