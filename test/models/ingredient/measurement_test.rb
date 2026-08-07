require "test_helper"

class Ingredient::MeasurementTest < ActiveSupport::TestCase
  EXPECTED_UNITS = {
    milligram: { aliases: %w[mg milligram milligrams], dimension: :mass, family: :mass, factor: Rational(1, 1_000), label: "mg" },
    gram: { aliases: %w[g gram grams], dimension: :mass, family: :mass, factor: Rational(1), label: "g" },
    kilogram: { aliases: %w[kg kilogram kilograms], dimension: :mass, family: :mass, factor: Rational(1_000), label: "kg" },
    ounce: { aliases: %w[oz ounce ounces], dimension: :mass, family: :mass, factor: Rational("28.349523125"), label: "oz" },
    pound: { aliases: %w[lb lbs pound pounds], dimension: :mass, family: :mass, factor: Rational("453.59237"), label: "lb" },
    milliliter: { aliases: %w[ml milliliter milliliters], dimension: :volume, family: :volume, factor: Rational(1), label: "mL" },
    liter: { aliases: %w[l liter liters], dimension: :volume, family: :volume, factor: Rational(1_000), label: "L" },
    teaspoon: { aliases: %w[tsp teaspoon teaspoons], dimension: :volume, family: :volume, factor: Rational("4.92892159375"), label: "tsp" },
    tablespoon: { aliases: %w[tbsp tablespoon tablespoons], dimension: :volume, family: :volume, factor: Rational("14.78676478125"), label: "tbsp" },
    cup: { aliases: %w[cup cups], dimension: :volume, family: :volume, factor: Rational("236.5882365"), label: "cup" },
    fluid_ounce: { aliases: [ "fl oz", "fluid ounce", "fluid ounces" ], dimension: :volume, family: :volume, factor: Rational("29.5735295625"), label: "fl oz" },
    can: { aliases: %w[can cans], dimension: :count, family: :can, factor: Rational(1), label: "can" },
    head: { aliases: %w[head heads], dimension: :count, family: :head, factor: Rational(1), label: "head" },
    package: { aliases: %w[package packages], dimension: :count, family: :package, factor: Rational(1), label: "package" },
    block: { aliases: %w[block blocks], dimension: :count, family: :block, factor: Rational(1), label: "block" }
  }.freeze

  test "declares an exact bounded alias registry" do
    expected_aliases = EXPECTED_UNITS.flat_map { |unit, definition| definition[:aliases].map { |alias_name| [ alias_name, unit ] } }.to_h

    assert_equal expected_aliases, Ingredient::Measurement::UNIT_ALIASES

    expected_aliases.each do |alias_name, canonical_unit|
      expected = EXPECTED_UNITS.fetch(canonical_unit)
      measurement = measurement(quantity: "2", unit: alias_name.upcase)

      assert_predicate measurement, :known?
      assert_equal expected[:dimension], measurement.dimension
      assert_equal expected[:family], measurement.family
      assert_equal canonical_unit, measurement.canonical_unit
      assert_equal expected[:factor], measurement.factor
      assert_equal expected[:label], measurement.normalized_label
      assert_equal Rational(2) * expected[:factor], measurement.normalized_quantity
    end
  end

  test "parses supported quantity syntax into reduced exact rationals" do
    {
      "2" => Rational(2),
      "1.25" => Rational(5, 4),
      "2/6" => Rational(1, 3),
      "1 2/4" => Rational(3, 2)
    }.each do |display_quantity, expected|
      assert_equal expected, measurement(quantity: display_quantity, unit: "g").quantity
    end
  end

  test "is immutable and owns copies of authored strings" do
    display_quantity = +"1 1/2"
    display_unit = +"Cups"
    measurement = measurement(quantity: display_quantity, unit: display_unit)

    display_quantity.replace("changed")
    display_unit.replace("changed")

    assert_predicate measurement, :frozen?
    assert_predicate measurement.display_quantity, :frozen?
    assert_predicate measurement.display_unit, :frozen?
    assert_equal "1 1/2", measurement.display_quantity
    assert_equal "Cups", measurement.display_unit
  end

  test "unknown quantities and units preserve their authored display values" do
    [ nil, "", "malformed", "1/0", "1 2/0", "to taste" ].each do |display_quantity|
      measurement = measurement(quantity: display_quantity, unit: " Cups ")

      assert_predicate measurement, :unknown?
      assert_equal :unknown, measurement.dimension
      assert_nil measurement.quantity
      display_quantity.nil? ? assert_nil(measurement.display_quantity) : assert_equal(display_quantity, measurement.display_quantity)
      assert_equal " Cups ", measurement.display_unit
    end

    unknown_unit = measurement(quantity: "2/3", unit: "pinch")
    assert_equal Rational(2, 3), unknown_unit.quantity
    assert_predicate unknown_unit, :unknown?
    assert_equal "2/3", unknown_unit.display_quantity
    assert_equal "pinch", unknown_unit.display_unit
  end

  test "numeric unitless quantities are generic counts" do
    [ nil, "", "  " ].each do |unit|
      measurement = measurement(quantity: "3", unit: unit)

      assert_equal :count, measurement.dimension
      assert_equal :count, measurement.family
      assert_equal :count, measurement.canonical_unit
      assert_equal Rational(1), measurement.factor
      assert_equal "count", measurement.normalized_label
      unit.nil? ? assert_nil(measurement.display_unit) : assert_equal(unit, measurement.display_unit)
    end
  end

  test "count aliases are compatible only inside their declared family" do
    EXPECTED_UNITS.select { |_unit, definition| definition[:dimension] == :count }.each_value do |definition|
      singular, plural = definition.fetch(:aliases)
      assert measurement(quantity: "1", unit: singular).compatible_with?(measurement(quantity: "1", unit: plural))
    end

    count_families = [ nil, "can", "head", "package", "block" ]
    count_families.combination(2) do |left, right|
      refute measurement(quantity: "1", unit: left).compatible_with?(measurement(quantity: "1", unit: right))
    end
  end

  test "converts compatible mass and volume units exactly" do
    assert_equal Rational(1_000), measurement(quantity: "1", unit: "kg").convert_to("g")
    assert_equal Rational(16), measurement(quantity: "1", unit: "lb").convert_to("oz")
    assert_equal Rational(1_000), measurement(quantity: "1", unit: "L").convert_to("mL")
    assert_equal Rational(48), measurement(quantity: "1", unit: "cup").convert_to("tsp")
    assert_equal Rational(16), measurement(quantity: "1", unit: "cup").convert_to("tbsp")
    assert_equal Rational(8), measurement(quantity: "1", unit: "cup").convert_to("fl oz")
  end

  test "rejects incompatible or unknown conversions" do
    gram = measurement(quantity: "1", unit: "g")
    cup = measurement(quantity: "1", unit: "cup")
    can = measurement(quantity: "1", unit: "can")
    package = measurement(quantity: "1", unit: "package")
    unknown = measurement(quantity: "1", unit: "metric cup")
    another_unknown = measurement(quantity: "1", unit: "imperial cup")

    refute gram.compatible_with?(cup)
    refute can.compatible_with?(package)
    refute can.compatible_with?(measurement(quantity: "1", unit: nil))
    refute unknown.compatible_with?(gram)
    refute unknown.compatible_with?(another_unknown)
    assert_nil gram.convert_to("cup")
    assert_nil can.convert_to("package")
    assert_nil unknown.convert_to("cup")
  end

  test "does not expose density or regional inference APIs" do
    measurement = measurement(quantity: "1", unit: "cup")

    refute_respond_to measurement, :density
    refute_respond_to measurement, :convert_with_density
    refute_respond_to measurement, :regional_standard
  end

  private
    def measurement(quantity:, unit:)
      Ingredient::Measurement.new(quantity:, unit:)
    end
end
