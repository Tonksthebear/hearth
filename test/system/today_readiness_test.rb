require "application_system_test_case"

class TodayReadinessTest < ApplicationSystemTestCase
  test "surfaces readiness badges and shopping attention on mobile width" do
    original_size = page.current_window.size

    travel_to Time.zone.local(2026, 7, 30, 12) do
      person_habits(:alex_water).habit_check_ins.destroy_all
      page.current_window.resize_to(390, 844)
      sign_in_via_browser users(:one)
      visit_and_wait_for_path root_path

      assert_equal 390, page.evaluate_script("window.innerWidth")
      assert_selector "[data-activity-kind='planned_meal'] [data-readiness-state]"
      assert_selector "[data-shopping-attention]", text: /Open shopping list \(1\)/
      assert_selector "[data-activity-kind='workout']"
      assert_selector "[data-activity-kind='simple_habit']"
      assert_link "Open shopping list (1)"
    end
  ensure
    page.current_window.resize_to(*original_size) if original_size
  end
end
