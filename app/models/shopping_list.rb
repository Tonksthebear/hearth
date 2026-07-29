class ShoppingList
  Entry = Data.define(:name, :amount, :unit)

  attr_reader :household, :start_date

  def initialize(household:, date:)
    @household = household
    @start_date = date.beginning_of_week(:monday)
  end

  def end_date
    start_date + 6.days
  end

  def entries
    ingredients
      .group_by { |ingredient| aggregation_key(ingredient) }
      .flat_map { |_, grouped| aggregate(grouped) }
      .sort_by { |entry| [ entry.name.downcase, entry.unit.to_s, entry.amount.to_s ] }
  end

  private
    def ingredients
      household.planned_meals
        .during(start_date..end_date)
        .includes(recipe: :recipe_ingredients)
        .flat_map { |planned_meal| planned_meal.recipe.recipe_ingredients }
    end

    def aggregation_key(ingredient)
      [ ingredient.name.squish.downcase, ingredient.unit.to_s.strip.presence ]
    end

    def aggregate(grouped)
      numeric, faithful = grouped.partition { |ingredient| parse_amount(ingredient.amount) }
      entries = faithful.map { |ingredient| entry_for(ingredient) }

      if numeric.any?
        total = numeric.sum { |ingredient| parse_amount(ingredient.amount) }
        entries << Entry.new(
          name: numeric.first.name.squish,
          amount: format_amount(total),
          unit: numeric.first.unit.to_s.strip.presence
        )
      end

      entries
    end

    def entry_for(ingredient)
      Entry.new(
        name: ingredient.name.squish,
        amount: ingredient.amount.to_s.strip.presence,
        unit: ingredient.unit.to_s.strip.presence
      )
    end

    def parse_amount(amount)
      value = amount.to_s.strip
      return if value.blank?

      if (match = value.match(/\A(\d+)\s+(\d+)\/(\d+)\z/))
        Rational(match[1].to_i, 1) + Rational(match[2].to_i, match[3].to_i)
      elsif value.match?(/\A\d+(?:\.\d+)?\z/)
        value.to_r
      elsif (match = value.match(/\A(\d+)\/(\d+)\z/))
        Rational(match[1].to_i, match[2].to_i)
      end
    rescue ZeroDivisionError
      nil
    end

    def format_amount(amount)
      return amount.numerator.to_s if amount.denominator == 1
      return amount.to_f.to_s if finite_decimal?(amount.denominator)

      "#{amount.numerator}/#{amount.denominator}"
    end

    def finite_decimal?(denominator)
      denominator /= 2 while denominator.even?
      denominator /= 5 while (denominator % 5).zero?
      denominator == 1
    end
end
