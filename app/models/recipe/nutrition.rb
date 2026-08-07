class Recipe::Nutrition
  Result = Data.define(:nutrient, :amount, :complete, :source_name, :provenance_status) do
    def formatted_amount
      Nutrient.format_amount(amount, unit: nutrient.unit)
    end
  end

  attr_reader :recipe

  def initialize(recipe)
    @recipe = recipe
  end

  def results
    @results ||= Nutrient.displayed.map { |nutrient| result_for(nutrient) }.freeze
  end

  def result_for(nutrient)
    estimated_result(nutrient)
  end

  private
    def estimated_result(nutrient)
      serving_count = decimal(recipe.serving_count)
      return missing_result(nutrient) unless serving_count&.positive?

      total = BigDecimal("0")
      known = false
      complete = active_ingredients.any?
      active_ingredients.each do |line|
        gram_weight = decimal(line.gram_weight)
        value = ingredient_values_for(line.ingredient)[nutrient.id]
        if gram_weight&.positive? && value
          total += gram_weight * decimal(value.amount_per_100_grams) / 100
          known = true
        else
          complete = false
        end
      end

      amount = known ? (total / serving_count).round(6, BigDecimal::ROUND_HALF_UP) : nil
      Result.new(
        nutrient: nutrient,
        amount: amount,
        complete: complete,
        source_name: recipe.source_name,
        provenance_status: recipe.provenance_status
      )
    end

    def missing_result(nutrient)
      Result.new(
        nutrient: nutrient,
        amount: nil,
        complete: false,
        source_name: recipe.source_name,
        provenance_status: recipe.provenance_status
      )
    end

    def active_ingredients
      @active_ingredients ||= recipe.recipe_ingredients.reject(&:marked_for_destruction?)
    end

    def ingredient_values_for(ingredient)
      @ingredient_values ||= {}
      @ingredient_values[ingredient.id] ||= ingredient.ingredient_nutrient_values.index_by(&:nutrient_id)
    end

    def decimal(value)
      BigDecimal(value.to_s) if value.present?
    end
end
