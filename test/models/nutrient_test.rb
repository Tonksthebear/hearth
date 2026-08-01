require "test_helper"
require Rails.root.join("db/migrate/20260731170000_create_nutrition_tracking_and_snapshots")

class NutrientTest < ActiveSupport::TestCase
  test "migration defaults model defaults and fixtures describe the same catalog" do
    migration = CreateNutritionTrackingAndSnapshots::DEFAULT_NUTRIENTS
    model = Nutrient::DEFAULTS.map { |row| row.values_at(:key, :name, :unit, :category, :display_order) }
    fixtures = Nutrient.displayed.map { |row| [ row.key, row.name, row.unit, row.category, row.display_order ] }

    assert_equal migration, model
    assert_equal model, fixtures
  end

  test "default reconciliation is idempotent and preserves exactly six rows" do
    assert_no_difference "Nutrient.count" do
      2.times { Nutrient.ensure_defaults! }
    end
    assert_equal 6, Nutrient.count
  end

  test "stable keys and units cannot change while display details can" do
    nutrient = nutrients(:protein)
    assert_not nutrient.update(key: "protein-new", unit: "mg")
    assert_includes nutrient.errors[:key], "cannot change"
    assert_includes nutrient.errors[:unit], "cannot change"
    nutrient.reload
    assert nutrient.update(name: "Protein total")
  end

  test "formatting rounds half up and preserves a known zero" do
    assert_equal "6.18 g", Nutrient.format_amount(BigDecimal("6.175"), unit: "g")
    assert_equal "0 g", Nutrient.format_amount(BigDecimal("0"), unit: "g")
    assert_equal "—", Nutrient.format_amount(nil, unit: "g")
  end
end
