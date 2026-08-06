require "test_helper"

class ShoppingListItem::PantryConfirmationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:one)
    @item = ShoppingList.for(household: households(:home), date: "2026-07-27").items.find_by!(name: "Lettuce")
  end

  test "the form prefills the outstanding deficit and states that checking off is not evidence" do
    get new_shopping_list_item_pantry_confirmation_path(@item)

    assert_response :success
    assert_select "form[action=?]", shopping_list_item_pantry_confirmation_path(@item)
    assert_select "input[name=?][value=?]", "pantry_confirmation[quantity]", "2"
    assert_select "input[name=?][value=?]", "pantry_confirmation[unit]", "head"
    assert_select "p", text: /checking the item off the list never does/i
  end

  test "confirming a purchase writes pantry evidence and clears the deficit on the next visit" do
    assert_difference "PantryItem.where(state: :confirmed).count", 1 do
      post shopping_list_item_pantry_confirmation_path(@item),
        params: { pantry_confirmation: { quantity: "2", unit: "head" } }
    end

    assert_redirected_to shopping_list_path(date: Date.new(2026, 7, 27))
    assert_response :see_other
    pantry = PantryItem.find_by!(household: households(:home), ingredient: ingredients(:lettuce))
    assert_equal [ "confirmed", Rational(2), "head" ], [ pantry.state, pantry.quantity, pantry.unit ]
    assert_equal PantryItem::PURCHASE_SOURCE, pantry.confirmation_source
    assert_equal people(:one), pantry.confirmed_by

    get shopping_list_path(date: "2026-07-27")
    assert_response :success
    refute ShoppingListItem.exists?(@item.id)
  end

  test "an unusable amount re-renders the form without writing pantry evidence" do
    assert_no_changes -> { pantry_items(:out_lettuce).reload.state } do
      post shopping_list_item_pantry_confirmation_path(@item),
        params: { pantry_confirmation: { quantity: "a bunch", unit: "head" } }
    end

    assert_response :unprocessable_entity
    assert_select "#pantry-confirmation-errors", text: /exact positive amount/
  end

  test "a manual row naming no canonical ingredient cannot reach the pantry" do
    assert_no_difference "PantryItem.count" do
      get new_shopping_list_item_pantry_confirmation_path(shopping_list_items(:manual_milk))
      assert_response :not_found

      post shopping_list_item_pantry_confirmation_path(shopping_list_items(:manual_milk)),
        params: { pantry_confirmation: { quantity: "1", unit: "gallon" } }
      assert_response :not_found

      post shopping_list_item_pantry_confirmation_path(0),
        params: { pantry_confirmation: { quantity: "1", unit: "head" } }
      assert_response :not_found
    end
  end

  test "anonymous confirmation attempts redirect to sign in" do
    delete session_path

    post shopping_list_item_pantry_confirmation_path(@item),
      params: { pantry_confirmation: { quantity: "1", unit: "head" } }

    assert_redirected_to new_session_path
  end
end
