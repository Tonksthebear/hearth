require "test_helper"

class Meal::NutritionSummaryTest < ActiveSupport::TestCase
  test "aggregates known zeros and values from historical snapshots" do
    summary = Meal::NutritionSummary.new([ meals(:alex_recipe_target_week) ])

    assert_equal "estimated", summary.status
    assert_equal BigDecimal("9.2625"), summary.totals.find { |total| total.key == "protein" }.amount
    assert_equal BigDecimal("0"), summary.totals.find { |total| total.key == "energy" }.amount
  end

  test "labels known partial totals incomplete when another item is unavailable" do
    summary = Meal::NutritionSummary.new([ meals(:alex_recipe_target_week), meals(:alex_ad_hoc_target_week) ])

    assert_equal "incomplete", summary.status
    assert_equal "9.26 g", summary.totals.find { |total| total.key == "protein" }.formatted_amount
  end
end
