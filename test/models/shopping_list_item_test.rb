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
    item = list.items.find_by!(name: "Lettuce")
    original_quantity = item.quantity

    assert item.apply_user_attributes(item.slice(:name, :quantity, :unit, :notes))
    refute item.reload.user_managed?

    plan = households(:home).planned_meals.create!(recipe: recipes(:salad), planned_on: Date.new(2026, 7, 31))
    plan.planned_meal_ingredients.active.each { |requirement| requirement.decide!(:missing) }
    list.reconcile!

    refute_equal original_quantity, item.reload.quantity
  end

  test "only a row naming a canonical ingredient can be confirmed into the pantry" do
    list = ShoppingList.for(household: households(:home), date: "2026-07-27")

    assert list.items.find_by!(name: "Lettuce").confirmable_into_pantry?
    refute shopping_list_items(:manual_milk).confirmable_into_pantry?
  end
end
