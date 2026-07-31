require "test_helper"

class ShoppingListTest < ActiveSupport::TestCase
  test "includes every household plan once while excluding logs and adjacent weeks" do
    entries = ShoppingList.new(
      household: households(:home),
      date: Date.new(2026, 7, 27)
    ).entries

    assert_equal [
      ShoppingList::Entry.new(name: "Carrots", amount: "2", unit: nil),
      ShoppingList::Entry.new(name: "Lettuce", amount: "2", unit: "head")
    ], entries
  end

  test "combines numeric amounts conservatively and keeps incompatible values faithful" do
    recipe = households(:home).recipes.create!(
      title: "Aggregation recipe",
      source_name: "Test",
      provenance_status: :observed,
      recipe_ingredients_attributes: [
        { display_quantity: "2", unit: nil, display_name: "Carrots", position: 1 },
        { display_quantity: "3", unit: "", display_name: " carrots ", position: 2 },
        { display_quantity: "1/2", unit: "cup", display_name: "CARROTS", position: 3 },
        { display_quantity: "1", unit: "cup", display_name: "Carrots", position: 4 },
        { display_quantity: "to taste", unit: "pinch", display_name: "Salt", position: 5 },
        { display_quantity: "as needed", unit: "pinch", display_name: "salt", position: 6 }
      ]
    )
    households(:home).planned_meals.create!(recipe: recipe, planned_on: Date.new(2026, 7, 30))

    entries = ShoppingList.new(
      household: households(:home),
      date: Date.new(2026, 7, 27)
    ).entries

    assert_includes entries, ShoppingList::Entry.new(name: "Carrots", amount: "7", unit: nil)
    assert_includes entries, ShoppingList::Entry.new(name: "CARROTS", amount: "1.5", unit: "cup")
    assert_includes entries, ShoppingList::Entry.new(name: "Salt", amount: "to taste", unit: "pinch")
    assert_includes entries, ShoppingList::Entry.new(name: "salt", amount: "as needed", unit: "pinch")
  end
end
