class ShoppingList < ApplicationRecord
  Requirement = Data.define(:key, :ingredient, :name, :quantity, :unit, :sources)
  # One confirmed allocation deficit, kept with the plan it was queued for.
  Source = Data.define(:planned_meal, :reservation) do
    # Provenance points at the decision row rather than the recipe line, so a
    # substitution flows into shopping without a second mapping.
    def planned_meal_ingredient_id = reservation.requirement.id
  end

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
    items.includes(shopping_list_item_sources: [ :planned_meal_ingredient, { planned_meal: :recipe } ]).to_a
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

    # Shopping work is whatever the household's own evidence could not cover. The
    # engine runs over the whole household queue so an out-of-week plan still
    # consumes the stock it was allocated, while only deficits belonging to this
    # week's plans become rows. Never filtered through PlannedMeal.visible_to:
    # the list is household operational data and counts every plan exactly once.
    def ordered_sources
      allocation = Household::PantryAllocation.new(household)

      allocation.planned_meals.flat_map do |planned_meal|
        next [] unless planned_meal.planned_on.between?(week_start, end_date)

        allocation.reservations_for(planned_meal)
          .select(&:deficit?)
          .map { |reservation| Source.new(planned_meal:, reservation:) }
      end
    end

    # Measurable deficits aggregate on the canonical unit, so alias spellings of
    # one unit land in one row while distinct units never convert into each
    # other. Anything the measurement foundation cannot classify stays tied to
    # the requirement that asked for it and is displayed exactly as authored.
    def generated_key_for(source)
      reservation = source.reservation
      if reservation.measurable?
        [ "deficit", reservation.ingredient.id, reservation.measurement.canonical_unit ].to_json
      else
        [ "deficit_source", source.planned_meal_ingredient_id ].to_json
      end
    end

    def requirement_for(key, sources)
      first = sources.first.reservation
      quantity, unit = if first.measurable?
        [ Ingredient::Measurement.format_quantity(sources.sum { |source| source.reservation.deficit_quantity }), canonical_unit_label(first.measurement) ]
      else
        [ first.display_quantity.to_s.strip.presence, normalized_unit(first.measurement.display_unit) ]
      end

      Requirement.new(
        key:,
        ingredient: first.ingredient,
        name: first.display_name.squish,
        quantity:,
        unit:,
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
        requirement.sources.each { |source| index[source.planned_meal_ingredient_id] = requirement.key }
      end

      ShoppingListItemSource
        .joins(:shopping_list_item)
        .where(shopping_list_items: { shopping_list_id: id })
        .find_each do |source|
          desired_key = desired_keys[source.planned_meal_ingredient_id]
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

    # The generic count group carries no unit token a shopper would recognize, so
    # it keeps the blank unit it has always displayed rather than the canonical
    # "count" label pantry rows persist.
    def canonical_unit_label(measurement)
      measurement.normalized_label unless measurement.canonical_unit == Ingredient::Measurement::GENERIC_COUNT.canonical_unit
    end
end
