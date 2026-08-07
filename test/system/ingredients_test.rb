require "application_system_test_case"

class IngredientsTest < ApplicationSystemTestCase
  test "nutrition index uses summaries on mobile and a comparison table on desktop" do
    sign_in_via_browser users(:one)

    page.driver.browser.execute_cdp(
      "Emulation.setDeviceMetricsOverride",
      width: 390,
      height: 900,
      deviceScaleFactor: 1,
      mobile: false
    )
    visit_and_wait_for_path ingredients_path

    assert_selector "[data-nutrition-list]", visible: :visible
    assert_no_selector "[data-nutrition-table]", visible: :visible
    assert_equal 0, page.evaluate_script("window.scrollX")

    page.driver.browser.execute_cdp(
      "Emulation.setDeviceMetricsOverride",
      width: 1200,
      height: 900,
      deviceScaleFactor: 1,
      mobile: false
    )
    visit_and_wait_for_path ingredients_path

    assert_selector "[data-nutrition-table]", visible: :visible
    assert_no_selector "[data-nutrition-list]", visible: :visible
  ensure
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end

  test "household can complete and clear an ingredient nutrition profile" do
    sign_in_via_browser users(:one)
    ingredient = ingredients(:blueberries)

    visit_and_wait_for_path edit_ingredient_path(ingredient)
    all("input[type='number']").each { |field| set_and_wait field, "1" }
    click_button_and_wait_for_path "Save nutrition", ingredients_path

    assert_text "Nutrition for Blueberries was updated."
    assert_selector "[data-nutrition-table] tr", text: /Blueberries.*Complete/m
    assert_equal Nutrient.displayed.count, ingredient.reload.ingredient_nutrient_values.count

    visit_and_wait_for_path edit_ingredient_path(ingredient)
    fill_in_and_wait_for_value "Energy (kcal)", ""
    click_button_and_wait_for_path "Save nutrition", ingredients_path

    assert_selector "[data-nutrition-table] tr", text: /Blueberries.*5 of 6 known/m
    assert_not ingredient.reload.ingredient_nutrient_values.exists?(nutrient: nutrients(:energy))
  end
end
