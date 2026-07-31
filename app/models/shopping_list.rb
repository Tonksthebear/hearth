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
    @entries ||= ingredients
      .group_by { |ingredient| aggregation_key(ingredient) }
      .flat_map { |_, grouped| aggregate(grouped) }
      .sort_by { |entry| [ entry.name.downcase, entry.unit.to_s, entry.amount.to_s ] }
  end

  private
    def ingredients
      household.planned_meals
        .during(start_date..end_date)
        .order(:planned_on, :id)
        .includes(recipe: :recipe_ingredients)
        .flat_map { |planned_meal| planned_meal.recipe.recipe_ingredients }
    end

    def aggregation_key(ingredient)
      [ ingredient.ingredient_id, ingredient.unit.to_s.strip.presence ]
    end

    def aggregate(grouped)
      numeric, faithful = grouped.partition(&:quantity)
      entries = faithful.map { |ingredient| entry_for(ingredient) }

      if numeric.any?
        total = numeric.sum(&:quantity)
        entries << Entry.new(
          name: numeric.first.display_name.squish,
          amount: format_amount(total),
          unit: numeric.first.unit.to_s.strip.presence
        )
      end

      entries
    end

    def entry_for(ingredient)
      Entry.new(
        name: ingredient.display_name.squish,
        amount: ingredient.display_quantity.to_s.strip.presence,
        unit: ingredient.unit.to_s.strip.presence
      )
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
