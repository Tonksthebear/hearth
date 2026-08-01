class Meal::NutritionSummary
  Total = Data.define(:key, :name, :unit, :amount, :complete, :estimated) do
    def formatted_amount
      Nutrient.format_amount(amount, unit: unit)
    end
  end

  attr_reader :meal_items

  def initialize(meals_or_items)
    records = Array(meals_or_items)
    @meal_items = if records.first.is_a?(Meal)
      records.flat_map { |meal| meal.meal_items.to_a }
    else
      records
    end
  end

  def totals
    @totals ||= begin
      grouped = meal_items.flat_map { |item| item.meal_item_nutrient_values.to_a }.group_by(&:snapshot_key)
      known_keys = grouped.keys
      ordered_keys = Nutrient.displayed.pluck(:key)
      ((ordered_keys & known_keys) + (known_keys - ordered_keys).sort).map do |key|
        values = grouped.fetch(key)
        first = values.first
        Total.new(
          key: key,
          name: first.snapshot_name,
          unit: first.snapshot_unit,
          amount: values.sum(BigDecimal("0")) { |value| BigDecimal(value.amount.to_s) }.round(6, BigDecimal::ROUND_HALF_UP),
          complete: complete?,
          estimated: values.any?(&:estimated?)
        )
      end.freeze
    end
  end

  def complete?
    meal_items.any? && meal_items.all?(&:nutrition_complete?)
  end

  def estimated?
    totals.any?(&:estimated)
  end

  def status
    return "unavailable" if totals.empty?
    return "incomplete" unless complete?
    return "estimated" if estimated?

    "complete"
  end
end
