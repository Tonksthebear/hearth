require "test_helper"

class ShoppingListItemSourceTest < ActiveSupport::TestCase
  test "an explicit household decision reads as household confirmed" do
    source = source_for(:sam_salad_lettuce)

    assert_equal :on_hand, source.confirmation_state
    assert_equal "On hand", source.confirmation_label
    assert source.household_confirmed?

    planned_meal_ingredients(:sam_salad_lettuce).decide!(:missing)
    assert_equal :missing, source.reload.confirmation_state
    assert_equal "Missing", source.confirmation_label
    assert source.household_confirmed?
  end

  test "a requirement only pantry evidence resolved is not household confirmed" do
    source = source_for(:shared_salad_lettuce)

    assert_equal :pantry_evidence, source.confirmation_state
    assert_equal "From pantry evidence", source.confirmation_label
    refute source.household_confirmed?
  end

  test "a substitution reports the replacement's decision and name" do
    requirement = planned_meal_ingredients(:soup_carrots_substituted)
    source = source_for(:soup_carrots_substituted)

    assert source.substituted?
    assert_equal "Blueberries", source.replacement_display_name
    assert_equal :pantry_evidence, source.confirmation_state

    requirement.decide_replacement!(:on_hand)
    assert_equal :on_hand, source.reload.confirmation_state
  end

  test "one requirement contributes to at most one shopping row" do
    source_for(:sam_salad_lettuce)
    duplicate = ShoppingListItemSource.new(
      shopping_list_item: shopping_list_items(:manual_milk),
      planned_meal_ingredient: planned_meal_ingredients(:sam_salad_lettuce)
    )

    refute duplicate.valid?
    assert_includes duplicate.errors[:planned_meal_ingredient_id], "has already been taken"
  end

  private
    def source_for(requirement)
      ShoppingListItemSource.create!(
        shopping_list_item: shopping_list_items(:completed_foil),
        planned_meal_ingredient: planned_meal_ingredients(requirement)
      )
    end
end
