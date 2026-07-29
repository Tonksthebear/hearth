require "test_helper"

class ShoppingListsControllerTest < ActionDispatch::IntegrationTest
  test "renders exactly the model projection for the household week" do
    sign_in_as users(:one)
    projection = ShoppingList.new(
      household: households(:home),
      date: Date.new(2026, 7, 27)
    )

    get shopping_list_path, params: { date: "2026-07-27" }

    assert_response :success
    rendered_lines = css_select("#shopping-list li").map { |node| node.text.squish }
    expected_lines = projection.entries.map do |entry|
      [ entry.amount, entry.unit, entry.name ].compact.join(" ")
    end
    assert_equal expected_lines, rendered_lines
  end

  test "invalid date safely renders the current household shopping week" do
    sign_in_as users(:one)

    travel_to Date.new(2026, 7, 27) do
      get shopping_list_path, params: { date: "not-a-date" }

      assert_response :success
      assert_select "p", text: /July 27, 2026/
      assert_select "#shopping-list li", count: 2
    end
  end
end
