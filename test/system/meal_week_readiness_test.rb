require "application_system_test_case"

class MealWeekReadinessTest < ApplicationSystemTestCase
  WEEK_START = Date.new(2026, 7, 27)

  test "meal week planned cards show readiness and shopping attention on mobile width" do
    original_size = page.current_window.size

    travel_to Time.zone.local(2026, 7, 30, 12) do
      page.current_window.resize_to(390, 844)
      sign_in_via_browser users(:one)
      visit_and_wait_for_path meal_week_path(date: WEEK_START)

      assert_equal 390, page.evaluate_script("window.innerWidth")
      assert_selector "[data-readiness-state='shopping_needed']", text: /Shopping needed/
      assert_selector "[data-readiness-state='needs_ingredient_check']", text: /Needs ingredient check/
      assert_selector "[data-shopping-attention]", text: /Open shopping list \(1\)/
      assert_link "Review ingredients", minimum: 1
    end
  ensure
    page.current_window.resize_to(*original_size) if original_size
  end
end
