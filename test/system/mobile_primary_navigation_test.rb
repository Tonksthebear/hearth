require "application_system_test_case"

class MobilePrimaryNavigationTest < ApplicationSystemTestCase
  test "mobile drawer exposes exactly Today Meals and Activities" do
    page.driver.browser.execute_cdp(
      "Emulation.setDeviceMetricsOverride",
      width: 390,
      height: 900,
      deviceScaleFactor: 1,
      mobile: false
    )

    sign_in_via_browser users(:one)
    find_button("Open sidebar").click

    within "nav[aria-label='Household and person context']" do
      assert_selector "a", count: 3, visible: :visible
      assert_link "Today"
      assert_link "Meals"
      assert_link "Activities"
      assert_no_link "Recipes"
      assert_no_link "Recovery"
    end

    click_link_and_wait_for_path "Meals", meal_week_path
    click_link_and_wait_for_path "Activities", activity_overview_path
    click_link_and_wait_for_path "Today", root_path
  ensure
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end
end
