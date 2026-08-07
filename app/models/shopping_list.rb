class ShoppingList < ApplicationRecord
  Requirement = Data.define(:key, :ingredient, :name, :quantity, :unit, :sources)
  Source = Data.define(:planned_meal, :recipe_ingredient)

  belongs_to :household
  has_many :items, -> { order(Arel.sql("completed_at IS NOT NULL"), :name, :id) },
    class_name: "ShoppingListItem", dependent: :destroy, inverse_of: :shopping_list

  validates :week_start, presence: true

  class << self
    def for(household:, date:)
      week_start = week_start_for(date)
      list = household.shopping_lists.create_or_find_by!(week_start:)
      list.reconcile!
    end

    def existing_for(household:, date:)
      household.shopping_lists.find_by(week_start: week_start_for(date))
    end

    def week_start_for(date)
      parsed_date = date.is_a?(String) ? Date.iso8601(date) : date.to_date
      parsed_date.beginning_of_week(:monday)
    end
  end

  def end_date
    week_start + 6.days
  end

  def unchecked_count
    items.where(completed_at: nil).count
  end

  def display_items
    @display_items ||= items.includes(shopping_list_item_sources: { planned_meal: :recipe }).to_a
  end

  def remaining_items
    display_items.reject(&:completed?)
  end

  def completed_items
    display_items.select(&:completed?)
  end

  def reconcile!
    with_lock do
      requirements = current_requirements
      detach_moved_sources(requirements)
      requirements.each { |requirement| reconcile_requirement(requirement) }
      remove_stale_requirements(requirements.map(&:key))
    end
    reload
  end

  private
    def current_requirements
      ordered_sources
        .group_by { |source| generated_key_for(source) }
        .map { |key, sources| requirement_for(key, sources) }
        .sort_by { |requirement| [ requirement.name.downcase, requirement.unit.to_s, requirement.key ] }
    end

    def ordered_sources
      household.planned_meals
        .during(week_start..end_date)
        .includes(recipe: { recipe_ingredients: :ingredient })
        .order(:planned_on, :id)
        .flat_map do |planned_meal|
          planned_meal.recipe.recipe_ingredients
            .sort_by { |recipe_ingredient| [ recipe_ingredient.position, recipe_ingredient.id ] }
            .map { |recipe_ingredient| Source.new(planned_meal:, recipe_ingredient:) }
        end
    end

    def generated_key_for(source)
      ingredient = source.recipe_ingredient
      if ingredient.quantity
        [ "ingredient", ingredient.ingredient_id, normalized_unit(ingredient.unit) ].to_json
      else
        [ "source", source.planned_meal.id, ingredient.id ].to_json
      end
    end

    def requirement_for(key, sources)
      first = sources.first.recipe_ingredient
      quantity = if first.quantity
        format_quantity(sources.sum { |source| source.recipe_ingredient.quantity })
      else
        first.display_quantity.to_s.strip.presence
      end

      Requirement.new(
        key:,
        ingredient: first.ingredient,
        name: first.display_name.squish,
        quantity:,
        unit: normalized_unit(first.unit),
        sources:
      )
    end

    def reconcile_requirement(requirement)
      item = items.find_or_initialize_by(generated_key: requirement.key)
      unless item.user_managed?
        item.assign_attributes(
          ingredient: requirement.ingredient,
          name: requirement.name,
          quantity: requirement.quantity,
          unit: requirement.unit
        )
      end
      item.save!
      item.reconcile_sources!(requirement.sources)
    end

    def detach_moved_sources(requirements)
      desired_keys = requirements.each_with_object({}) do |requirement, index|
        requirement.sources.each do |source|
          index[[ source.planned_meal.id, source.recipe_ingredient.id ]] = requirement.key
        end
      end

      ShoppingListItemSource
        .joins(:shopping_list_item)
        .where(shopping_list_items: { shopping_list_id: id })
        .find_each do |source|
          desired_key = desired_keys[[ source.planned_meal_id, source.recipe_ingredient_id ]]
          source.destroy! if desired_key != source.shopping_list_item.generated_key
        end
    end

    def remove_stale_requirements(current_keys)
      items.where.not(generated_key: nil).where.not(generated_key: current_keys).find_each do |item|
        item.shopping_list_item_sources.destroy_all
        item.destroy! unless item.user_managed? || item.completed?
      end
    end

    def normalized_unit(unit)
      unit.to_s.strip.presence
    end

    def format_quantity(quantity)
      return quantity.numerator.to_s if quantity.denominator == 1
      return quantity.to_f.to_s if finite_decimal?(quantity.denominator)

      "#{quantity.numerator}/#{quantity.denominator}"
    end

    def finite_decimal?(denominator)
      denominator /= 2 while denominator.even?
      denominator /= 5 while (denominator % 5).zero?
      denominator == 1
    end
end
