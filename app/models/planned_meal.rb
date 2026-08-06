class PlannedMeal < ApplicationRecord
  belongs_to :household
  belongs_to :person, optional: true
  belongs_to :recipe
  has_many :meals, dependent: :restrict_with_exception
  has_many :shopping_list_item_sources, dependent: :destroy
  # Declared ahead of the requirements it references: dependent teardown runs in
  # declaration order, and the consumption ledger restricts deleting a
  # requirement that drew stock.
  has_many :pantry_consumptions, dependent: :destroy, inverse_of: :planned_meal
  has_many :planned_meal_ingredients, -> { ordered }, dependent: :destroy, inverse_of: :planned_meal

  # Snapshots must be current before anything downstream reads this plan's
  # requirements, so this callback is declared ahead of shopping reconciliation.
  after_commit :reconcile_ingredient_snapshots, on: %i[ create update ]
  after_commit :reconcile_shopping_lists, on: %i[ create update destroy ]

  scope :during, ->(date_range) { where(planned_on: date_range) }
  scope :visible_to, ->(person) { where(person_id: [ nil, person.id ]) }
  # The allocation queue. A plan participates while it has no Meal rows at all:
  # the first conversion is the household's cooking event, and the extra Meal rows
  # a shared plan accumulates are per-person nutrition records rather than second
  # cooking events. Household-scoped on purpose — visible_to is display-only, and
  # filtering by person here would reserve a shared plan's stock once per eater.
  scope :allocatable, -> { where.missing(:meals) }
  # Contract order: an explicit household override first, then ascending date,
  # then stable planned-meal identity. Unprioritized plans sort last among
  # overrides rather than first, which is SQLite's default for NULL.
  scope :in_allocation_order, -> {
    order(arel_table[:allocation_priority].asc.nulls_last, :planned_on, :id)
  }

  validates :planned_on, presence: true
  validates :recipe_scale, numericality: { greater_than: 0 }
  validate :person_belongs_to_household
  validate :recipe_belongs_to_household
  validate :references_are_available

  attr_accessor :invalid_person_reference

  def converted_meal_for(person)
    meals.loaded? ? meals.detect { |meal| meal.person_id == person.id } : meals.find_by(person:)
  end

  def convertible_by?(person, today: Date.current)
    planned_on <= today && (person_id.nil? || person_id == person.id)
  end

  def convert_for!(person, today: Date.current)
    with_lock do
      existing = meals.find_by(person:)
      return existing if existing
      unless convertible_by?(person, today:)
        errors.add(:base, "This planned meal is not available to convert.")
        raise ActiveRecord::RecordInvalid, self
      end

      # The first conversion is the household's cooking event, so the stock this
      # plan was holding is drawn exactly once. Exactly-once is carried by the
      # allocatable queue itself — a plan with any Meal has already left it and
      # reserves nothing — and this check is the cheap short-circuit that skips
      # building a projection already known to be empty for this plan.
      # Reservations are read before the Meal that removes it from the queue.
      reservations = meals.exists? ? [] : Household::PantryAllocation.new(household).reservations_for(self)

      meal = meals.create!(
        household: household,
        person: person,
        eaten_on: planned_on,
        meal_items_attributes: [ { source_kind: :recipe, recipe: recipe } ]
      )
      reservations.each { |reservation| draw_from_pantry(reservation, person: person) }
      meal
    end
  rescue ActiveRecord::RecordNotUnique
    meals.find_by!(person:)
  end

  # Undo for the cooking event: once the last Meal is gone the plan re-enters the
  # allocation queue, so every draw it still holds is settled. Replay credits
  # nothing further because the ledger, not inference, is the guard.
  def release_pantry_consumptions!(person:, at: Time.current)
    with_lock do
      pantry_consumptions.active.each { |consumption| consumption.release!(person: person, at: at) } unless meals.exists?
    end
    self
  end

  # Moves this plan ahead of another one in allocation order without touching
  # either date. Priorities only ever grow, so the positive check constraint holds
  # and no plan needs a second pass to make room.
  def prioritize_before!(other)
    raise ArgumentError, "A planned meal can only be prioritized within its own household" unless other.household_id == household_id

    transaction do
      # SQLite drops FOR UPDATE, so the ordering is recomputed from the row this
      # transaction reloaded rather than from a possibly stale in-memory copy.
      target = self.class.lock.find(other.id).allocation_priority

      if target
        household.planned_meals
          .where(allocation_priority: target..)
          .where.not(id: id)
          .update_all("allocation_priority = allocation_priority + 1")
        update!(allocation_priority: target)
      else
        update!(allocation_priority: household.planned_meals.maximum(:allocation_priority).to_i + 1)
      end
    end
    self
  end

  # Restores date-plus-stable-identity ordering. Gaps left in the remaining
  # priorities are harmless: allocation orders by value, not by adjacency.
  def clear_allocation_priority!
    update!(allocation_priority: nil)
    self
  end

  # Brings this plan's own ingredient requirements back in line with its recipe
  # and scale. Obsolete requirements leave the active set before fresh ones
  # arrive, because positional recipe edits can repoint several source rows at
  # once and one source may stay active only once per plan.
  def reconcile_ingredient_snapshots!(reason: "requirement_changed")
    transaction do
      # Lock the row without reloading self: the shopping callback that runs
      # after this one still needs our previous_changes.
      self.class.lock.find(id)

      requirements = current_requirements
      retained = retire_obsolete_requirements(requirements, reason)
      apply_requirements(requirements, retained)
    end
    self
  end

  class << self
    def build_for(household:, planned_on:, recipe_id:, person_id: nil)
      new(
        household: household,
        planned_on: planned_on,
        recipe: household.recipes.find_by(id: recipe_id),
        person: person_id.present? ? household.people.find_by(id: person_id) : nil,
        invalid_person_reference: person_id.present? && !household.people.exists?(id: person_id)
      )
    end
  end

  private
    # Draws one requirement's reservation out of the pantry and records what it
    # actually got. Nothing here may block logging: a row that is no longer
    # confirmed, no longer compatible, or already emptier than the projection
    # believed is skipped rather than raised, and the amount is always clamped to
    # what the reloaded row currently holds. A rejected adjustment is retried once
    # against a freshly read row, then abandoned.
    def draw_from_pantry(reservation, person:, at: Time.current)
      wanted = reservation.reserved_quantity
      return if wanted.nil? || !wanted.positive?

      2.times do
        # The projection's copy is a snapshot; the row this transaction reads is
        # what the draw has to be computed from.
        pantry = PantryItem.find_by(household_id: household_id, ingredient_id: reservation.ingredient.id)
        return unless pantry&.confirmed?
        return unless reservation.measurement.compatible_with?(pantry.measurement)

        unit = pantry.unit
        drawn = [ wanted * reservation.measurement.factor / pantry.measurement.factor, pantry.quantity ].min
        return unless drawn.positive?

        begin
          pantry.adjust!(delta: -drawn, unit: unit, source: PantryConsumption::CONSUMPTION_SOURCE, confirmed_by: person, confirmed_at: at)
        rescue ActiveRecord::RecordInvalid
          next
        end

        return pantry_consumptions.create!(
          planned_meal_ingredient: reservation.requirement,
          ingredient_id: reservation.ingredient.id,
          quantity_numerator: drawn.numerator,
          quantity_denominator: drawn.denominator,
          unit: unit
        )
      end
    end

    def reconcile_ingredient_snapshots
      reconcile_ingredient_snapshots!(reason: supersession_reason_for_changes)
    end

    def supersession_reason_for_changes
      return "recipe_changed" if previous_changes.key?("recipe_id")
      return "recipe_scale_changed" if previous_changes.key?("recipe_scale")

      "requirement_changed"
    end

    def current_requirements
      return [] unless recipe

      scale = recipe_scale.to_r
      recipe.recipe_ingredients.reorder(:position, :id).map do |recipe_ingredient|
        required = recipe_ingredient.quantity
        quantity = required * scale if required
        {
          source_recipe_id: recipe_ingredient.recipe_id,
          source_recipe_ingredient_id: recipe_ingredient.id,
          ingredient_id: recipe_ingredient.ingredient_id,
          display_name: recipe_ingredient.display_name,
          display_quantity: recipe_ingredient.display_quantity,
          unit: recipe_ingredient.unit,
          quantity_numerator: quantity&.numerator,
          quantity_denominator: quantity&.denominator,
          position: recipe_ingredient.position
        }
      end
    end

    def retire_obsolete_requirements(requirements, reason)
      wanted = requirements.index_by { |requirement| requirement[:source_recipe_ingredient_id] }

      planned_meal_ingredients.active.to_a.each_with_object({}) do |row, retained|
        requirement = wanted[row.source_recipe_ingredient_id]
        if requirement && requirement_fingerprint(requirement) == row.requirement_fingerprint
          retained[row.source_recipe_ingredient_id] = row
        else
          row.discard_or_supersede!(reason)
        end
      end
    end

    def apply_requirements(requirements, retained)
      requirements.each do |requirement|
        row = retained[requirement[:source_recipe_ingredient_id]]
        if row
          row.update!(requirement.slice(*PlannedMealIngredient::PRESENTATION_ATTRIBUTES))
        else
          planned_meal_ingredients.create!(requirement)
        end
      end
    end

    def requirement_fingerprint(requirement)
      PlannedMealIngredient.requirement_fingerprint(
        ingredient_id: requirement[:ingredient_id],
        display_quantity: requirement[:display_quantity],
        unit: requirement[:unit],
        quantity: exact_quantity(requirement)
      )
    end

    def exact_quantity(requirement)
      numerator, denominator = requirement.values_at(:quantity_numerator, :quantity_denominator)
      Rational(numerator, denominator) if numerator && denominator&.positive?
    end

    def reconcile_shopping_lists
      affected_periods.each do |household_id, week_start, create_if_missing|
        household = Household.find_by(id: household_id)
        next unless household

        list = if create_if_missing
          household.shopping_lists.create_or_find_by!(week_start:)
        else
          household.shopping_lists.find_by(week_start:)
        end
        list&.reconcile!
      end
    end

    def affected_periods
      if destroyed?
        return [ [ household_id, planned_on&.beginning_of_week(:monday), false ] ]
      end

      old_household_id, new_household_id = previous_changes["household_id"] || [ household_id, household_id ]
      old_planned_on, new_planned_on = previous_changes["planned_on"] || [ planned_on, planned_on ]

      periods = []
      periods << [ old_household_id, old_planned_on&.beginning_of_week(:monday), false ] if old_planned_on != new_planned_on || old_household_id != new_household_id
      periods << [ new_household_id, new_planned_on&.beginning_of_week(:monday), true ]
      periods.compact.reject { |household_id, week_start, _| household_id.blank? || week_start.blank? }.uniq
    end

    def person_belongs_to_household
      errors.add(:person, "must belong to this household") if person && person.household != household
    end

    def recipe_belongs_to_household
      errors.add(:recipe, "must belong to this household") if recipe && recipe.household != household
    end

    def references_are_available
      errors.add(:person, "is not available") if invalid_person_reference
    end
end
