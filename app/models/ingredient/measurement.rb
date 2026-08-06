class Ingredient::Measurement
  Unit = Data.define(:dimension, :family, :canonical_unit, :factor, :normalized_label)

  UNITS = {
    milligram: Unit.new(dimension: :mass, family: :mass, canonical_unit: :milligram, factor: Rational(1, 1_000), normalized_label: "mg".freeze),
    gram: Unit.new(dimension: :mass, family: :mass, canonical_unit: :gram, factor: Rational(1), normalized_label: "g".freeze),
    kilogram: Unit.new(dimension: :mass, family: :mass, canonical_unit: :kilogram, factor: Rational(1_000), normalized_label: "kg".freeze),
    ounce: Unit.new(dimension: :mass, family: :mass, canonical_unit: :ounce, factor: Rational("28.349523125"), normalized_label: "oz".freeze),
    pound: Unit.new(dimension: :mass, family: :mass, canonical_unit: :pound, factor: Rational("453.59237"), normalized_label: "lb".freeze),
    milliliter: Unit.new(dimension: :volume, family: :volume, canonical_unit: :milliliter, factor: Rational(1), normalized_label: "mL".freeze),
    liter: Unit.new(dimension: :volume, family: :volume, canonical_unit: :liter, factor: Rational(1_000), normalized_label: "L".freeze),
    teaspoon: Unit.new(dimension: :volume, family: :volume, canonical_unit: :teaspoon, factor: Rational("4.92892159375"), normalized_label: "tsp".freeze),
    tablespoon: Unit.new(dimension: :volume, family: :volume, canonical_unit: :tablespoon, factor: Rational("14.78676478125"), normalized_label: "tbsp".freeze),
    cup: Unit.new(dimension: :volume, family: :volume, canonical_unit: :cup, factor: Rational("236.5882365"), normalized_label: "cup".freeze),
    fluid_ounce: Unit.new(dimension: :volume, family: :volume, canonical_unit: :fluid_ounce, factor: Rational("29.5735295625"), normalized_label: "fl oz".freeze),
    can: Unit.new(dimension: :count, family: :can, canonical_unit: :can, factor: Rational(1), normalized_label: "can".freeze),
    head: Unit.new(dimension: :count, family: :head, canonical_unit: :head, factor: Rational(1), normalized_label: "head".freeze),
    package: Unit.new(dimension: :count, family: :package, canonical_unit: :package, factor: Rational(1), normalized_label: "package".freeze),
    block: Unit.new(dimension: :count, family: :block, canonical_unit: :block, factor: Rational(1), normalized_label: "block".freeze)
  }.freeze

  UNIT_ALIASES = {
    "mg" => :milligram, "milligram" => :milligram, "milligrams" => :milligram,
    "g" => :gram, "gram" => :gram, "grams" => :gram,
    "kg" => :kilogram, "kilogram" => :kilogram, "kilograms" => :kilogram,
    "oz" => :ounce, "ounce" => :ounce, "ounces" => :ounce,
    "lb" => :pound, "lbs" => :pound, "pound" => :pound, "pounds" => :pound,
    "ml" => :milliliter, "milliliter" => :milliliter, "milliliters" => :milliliter,
    "l" => :liter, "liter" => :liter, "liters" => :liter,
    "tsp" => :teaspoon, "teaspoon" => :teaspoon, "teaspoons" => :teaspoon,
    "tbsp" => :tablespoon, "tablespoon" => :tablespoon, "tablespoons" => :tablespoon,
    "cup" => :cup, "cups" => :cup,
    "fl oz" => :fluid_ounce, "fluid ounce" => :fluid_ounce, "fluid ounces" => :fluid_ounce,
    "can" => :can, "cans" => :can,
    "head" => :head, "heads" => :head,
    "package" => :package, "packages" => :package,
    "block" => :block, "blocks" => :block
  }.freeze

  GENERIC_COUNT = Unit.new(
    dimension: :count,
    family: :count,
    canonical_unit: :count,
    factor: Rational(1),
    normalized_label: "count".freeze
  )

  attr_reader :display_quantity, :display_unit, :quantity

  def initialize(quantity:, unit:)
    @display_quantity = immutable_copy(quantity)
    @display_unit = immutable_copy(unit)
    @quantity = parse_quantity(quantity)
    @unit = resolve_unit(unit)
    freeze
  end

  def known?
    quantity.present? && @unit.present?
  end

  def unknown?
    !known?
  end

  def dimension
    known? ? @unit.dimension : :unknown
  end

  def family
    @unit.family if known?
  end

  def canonical_unit
    @unit.canonical_unit if known?
  end

  def factor
    @unit.factor if known?
  end

  def normalized_label
    @unit.normalized_label if known?
  end

  def normalized_quantity
    quantity * factor if known?
  end

  def compatible_with?(other)
    return false unless other.is_a?(self.class) && known? && other.known?
    return false unless dimension == other.dimension

    dimension != :count || family == other.family
  end

  def convert_to(target_unit)
    target = self.class.new(quantity: 1, unit: target_unit)
    return unless compatible_with?(target)

    normalized_quantity / target.factor
  end

  private
    def immutable_copy(value)
      value.is_a?(String) ? value.dup.freeze : value
    end

    def parse_quantity(value)
      value = value.to_s.strip
      return if value.blank?

      if (match = value.match(/\A(\d+)\s+(\d+)\/(\d+)\z/))
        Rational(match[1].to_i, 1) + Rational(match[2].to_i, match[3].to_i)
      elsif value.match?(/\A\d+(?:\.\d+)?\z/)
        Rational(value)
      elsif (match = value.match(/\A(\d+)\/(\d+)\z/))
        Rational(match[1].to_i, match[2].to_i)
      end
    rescue ArgumentError, ZeroDivisionError
      nil
    end

    def resolve_unit(value)
      normalized = value.to_s.squish.downcase
      return GENERIC_COUNT if normalized.blank?

      UNITS[UNIT_ALIASES[normalized]]
    end
end
