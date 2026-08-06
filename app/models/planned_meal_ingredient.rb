class PlannedMealIngredient < ApplicationRecord
  # Lifecycle reasons live outside the contract's canonical decision vocabulary:
  # they explain why a plan requirement stopped being current, not what the
  # household decided about it.
  SUPERSESSION_REASONS = %w[ recipe_changed recipe_scale_changed requirement_changed source_removed ].freeze
  PRESENTATION_ATTRIBUTES = %i[
    source_recipe_id ingredient_id display_name display_quantity unit
    quantity_numerator quantity_denominator position
  ].freeze

  belongs_to :planned_meal, inverse_of: :planned_meal_ingredients
  belongs_to :source_recipe, class_name: "Recipe", optional: true, inverse_of: :planned_meal_ingredients
  belongs_to :source_recipe_ingredient, class_name: "RecipeIngredient", optional: true, inverse_of: :planned_meal_ingredients
  belongs_to :ingredient, inverse_of: :planned_meal_ingredients
  belongs_to :replacement_ingredient, class_name: "Ingredient", optional: true, inverse_of: :replacement_planned_meal_ingredients

  enum :decision, {
    unknown: "unknown",
    on_hand: "on_hand",
    missing: "missing",
    substituted: "substituted",
    not_needed: "not_needed"
  }, validate: true

  enum :replacement_decision, {
    unknown: "unknown",
    on_hand: "on_hand",
    missing: "missing"
  }, prefix: :replacement, validate: { allow_nil: true }

  scope :active, -> { where(superseded_at: nil) }
  scope :superseded, -> { where.not(superseded_at: nil) }
  scope :ordered, -> { order(:position, :id) }

  validates :display_name, presence: true
  validates :position, numericality: { only_integer: true, greater_than: 0 }
  validate :active_rows_keep_their_source
  validate :supersession_is_paired
  validate :replacement_matches_decision
  validate :ingredients_belong_to_the_plan_household
  validate :superseded_rows_are_immutable, on: :update

  def quantity
    exact_quantity(quantity_numerator, quantity_denominator)
  end

  def replacement_quantity
    exact_quantity(replacement_quantity_numerator, replacement_quantity_denominator)
  end

  def active?
    superseded_at.nil?
  end

  # An untouched unknown row carries no household work, so an obsolete one is
  # discarded rather than kept as provenance.
  def untouched?
    unknown? && decided_at.nil?
  end

  def resolved?
    !untouched?
  end

  # Semantic identity of the requirement this row stands for. Presentation
  # changes such as whitespace, casing, or position keep the same fingerprint;
  # a different ingredient, required amount, or unit does not.
  def requirement_fingerprint
    self.class.requirement_fingerprint(
      ingredient_id: ingredient_id,
      display_quantity: display_quantity,
      unit: unit,
      quantity: quantity
    )
  end

  def decide!(decision, at: Time.current)
    update!(decision: decision, decided_at: at, **blank_replacement_attributes)
  end

  def reset_decision!(at: Time.current)
    decide!(:unknown, at: at)
  end

  def substitute!(ingredient:, display_quantity: nil, unit: nil, display_name: nil, at: Time.current)
    measurement = Ingredient::Measurement.new(quantity: display_quantity, unit: unit)
    update!(
      decision: :substituted,
      decided_at: at,
      replacement_ingredient: ingredient,
      replacement_display_name: display_name.presence || ingredient&.name,
      replacement_display_quantity: display_quantity,
      replacement_unit: unit,
      replacement_quantity_numerator: measurement.quantity&.numerator,
      replacement_quantity_denominator: measurement.quantity&.denominator,
      replacement_decision: :unknown
    )
  end

  def decide_replacement!(decision, at: Time.current)
    update!(replacement_decision: decision, decided_at: at)
  end

  def supersede!(reason, at: Time.current)
    update!(superseded_at: at, superseded_reason: reason)
  end

  # Obsolete requirements leave the active set: resolved ones stay as immutable
  # provenance, untouched ones simply disappear.
  def discard_or_supersede!(reason, at: Time.current)
    resolved? ? supersede!(reason, at: at) : destroy!
  end

  class << self
    def requirement_fingerprint(ingredient_id:, display_quantity:, unit:, quantity:)
      measurement = Ingredient::Measurement.new(quantity: display_quantity, unit: unit)

      if measurement.known? && quantity
        [ :known, ingredient_id, quantity.numerator, quantity.denominator, measurement.canonical_unit, measurement.family ]
      elsif quantity
        # Hearth cannot prove an unrecognized unit token means the same thing
        # after an edit, so the token itself is part of the requirement.
        [ :raw_unit, ingredient_id, quantity.numerator, quantity.denominator, comparison_token(unit) ]
      else
        [ :free_text, ingredient_id, comparison_token(display_quantity), comparison_token(unit) ]
      end
    end

    def comparison_token(value)
      value.to_s.squish.downcase(:fold)
    end
  end

  private
    def exact_quantity(numerator, denominator)
      return unless numerator && denominator&.positive?

      Rational(numerator, denominator)
    end

    def blank_replacement_attributes
      {
        replacement_ingredient: nil,
        replacement_display_name: nil,
        replacement_display_quantity: nil,
        replacement_unit: nil,
        replacement_quantity_numerator: nil,
        replacement_quantity_denominator: nil,
        replacement_decision: nil
      }
    end

    def active_rows_keep_their_source
      return unless active?
      return if source_recipe_id && source_recipe_ingredient_id

      errors.add(:base, "An active requirement must keep its recipe source")
    end

    def supersession_is_paired
      if superseded_at.present? != superseded_reason.present?
        errors.add(:superseded_reason, "must accompany a supersession timestamp")
      elsif superseded_reason.present? && !superseded_reason.in?(SUPERSESSION_REASONS)
        errors.add(:superseded_reason, "is not a supersession reason")
      end
    end

    def replacement_matches_decision
      if substituted?
        errors.add(:replacement_ingredient, "must be chosen for a substitution") if replacement_ingredient.blank?
        errors.add(:replacement_display_name, "must describe the replacement") if replacement_display_name.blank?
        errors.add(:replacement_decision, "must start unresolved") if replacement_decision.blank?
      elsif replacement_attributes_present?
        errors.add(:base, "A replacement only belongs to a substituted requirement")
      end
    end

    def replacement_attributes_present?
      replacement_ingredient_id.present? || replacement_display_name.present? ||
        replacement_display_quantity.present? || replacement_unit.present? ||
        replacement_quantity_numerator.present? || replacement_decision.present?
    end

    def ingredients_belong_to_the_plan_household
      household = planned_meal&.household
      return unless household

      errors.add(:ingredient, "must belong to this household") if ingredient && ingredient.household_id != household.id
      if replacement_ingredient && replacement_ingredient.household_id != household.id
        errors.add(:replacement_ingredient, "must belong to this household")
      end
    end

    def superseded_rows_are_immutable
      return if superseded_at_in_database.nil?

      errors.add(:base, "A superseded requirement cannot be changed") if changed?
    end
end
