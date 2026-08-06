# What one planned-meal requirement actually drew out of the pantry when the
# household cooked, recorded in the pantry row's own unit at the moment of the
# draw. Release credits back exactly this amount rather than recomputing from
# allocation, which drifts as pantry evidence, dates, priorities, and sibling
# plans change.
class PantryConsumption < ApplicationRecord
  # Release reasons are implementation lifecycle values that explain why a draw
  # was or was not credited back. They are deliberately outside the contract's
  # canonical readiness, decision, and pantry vocabularies, matching how
  # PlannedMealIngredient treats supersession reasons.
  RELEASE_REASONS = %w[ credited evidence_weakened evidence_depleted evidence_cleared evidence_absent unit_incompatible ].freeze
  FORFEIT_REASONS = {
    "low" => "evidence_weakened",
    "out" => "evidence_depleted",
    "unknown" => "evidence_cleared"
  }.freeze
  CONSUMPTION_SOURCE = "meal_consumption".freeze
  RELEASE_SOURCE = "meal_consumption_undo".freeze

  belongs_to :planned_meal, inverse_of: :pantry_consumptions
  belongs_to :planned_meal_ingredient, inverse_of: :pantry_consumptions
  belongs_to :ingredient, inverse_of: :pantry_consumptions

  scope :active, -> { where(released_at: nil) }
  scope :released, -> { where.not(released_at: nil) }

  validates :unit, presence: true
  validate :requirement_belongs_to_the_plan
  validate :ingredient_belongs_to_the_plan_household
  validate :release_is_paired
  validate :released_rows_are_immutable, on: :update

  def quantity
    return unless quantity_numerator && quantity_denominator&.positive?

    Rational(quantity_numerator, quantity_denominator)
  end

  # The recorded draw as a measurement. The pantry stores generic count under
  # Ingredient::Measurement's canonical label, which the PORO only reads back
  # through a blank unit, so that one label is translated here the same way
  # PantryItem translates it.
  def measurement
    Ingredient::Measurement.new(quantity: quantity, unit: generic_count? ? nil : unit)
  end

  def active?
    released_at.nil?
  end

  # Credits the recorded amount back when the household's evidence still admits
  # it, and always leaves a marker. A newer human assertion — low, out, unknown,
  # a deleted row, or a re-confirmation in another unit family — is preserved
  # rather than overwritten with an inferred number, so that credit is forfeited
  # and the reason stays diagnosable.
  def release!(person:, at: Time.current)
    update!(released_at: at, released_reason: credit_back(person: person, at: at))
    self
  end

  private
    def generic_count?
      unit.to_s.squish.casecmp?(PantryItem::GENERIC_COUNT_UNIT)
    end

    def credit_back(person:, at:)
      pantry = PantryItem.find_by(household_id: planned_meal.household_id, ingredient_id: ingredient_id)
      return "evidence_absent" if pantry.nil?
      return FORFEIT_REASONS.fetch(pantry.state) unless pantry.confirmed?
      return "unit_incompatible" unless measurement.compatible_with?(pantry.measurement)

      pantry.adjust!(delta: quantity, unit: unit, source: RELEASE_SOURCE, confirmed_by: person, confirmed_at: at)
      "credited"
    end

    # References the association object rather than guarding on whether it is
    # loaded: direct foreign-key assignment leaves it unloaded and would turn a
    # cross-plan reference into a database error instead of a validation one.
    def requirement_belongs_to_the_plan
      return if planned_meal_ingredient.blank? || planned_meal_ingredient.planned_meal_id == planned_meal_id

      errors.add(:planned_meal_ingredient, "must belong to this planned meal")
    end

    def ingredient_belongs_to_the_plan_household
      household_id = planned_meal&.household_id
      return if household_id.blank? || ingredient.blank? || ingredient.household_id == household_id

      errors.add(:ingredient, "must belong to this household")
    end

    def release_is_paired
      if released_at.present? != released_reason.present?
        errors.add(:released_reason, "must accompany a release timestamp")
      elsif released_reason.present? && !released_reason.in?(RELEASE_REASONS)
        errors.add(:released_reason, "is not a release reason")
      end
    end

    def released_rows_are_immutable
      return if released_at_in_database.nil?

      errors.add(:base, "A released pantry consumption cannot be changed") if changed?
    end
end
