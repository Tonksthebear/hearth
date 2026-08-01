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

  test "saving unchanged generated attributes does not make the item user managed" do
    list = ShoppingList.for(household: households(:home), date: "2026-07-27")
    item = list.items.find_by!(name: "Carrots")
    original_quantity = item.quantity

    assert item.apply_user_attributes(item.slice(:name, :quantity, :unit, :notes))
    refute item.reload.user_managed?

    households(:home).planned_meals.create!(recipe: recipes(:observed_soup), planned_on: Date.new(2026, 7, 31))

    refute_equal original_quantity, item.reload.quantity
  end
end
