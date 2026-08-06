class PlannedMealIngredient < ApplicationRecord
  # Lifecycle reasons live outside the contract's canonical decision vocabulary:
  # they explain why a plan requirement stopped being current, not what the
  # household decided about it.
  SUPERSESSION_REASONS = %w[ recipe_changed recipe_scale_changed requirement_changed source_removed ].freeze
  PRESENTATION_ATTRIBUTES = %i[
    source_recipe_id ingredient_id display_name display_quantity unit
    quantity_numerator quantity_denominator position
  ].freeze
  # The contract's canonical user-facing labels. They are vocabulary rather than
  # copy — "Check ingredient" is what an unresolved decision is called — so they
  # live with the enum they name and PantryReadinessContractTest pins them.
  DECISION_LABELS = {
    "unknown" => "Check ingredient",
    "on_hand" => "On hand",
    "missing" => "Missing",
    "substituted" => "Substituted",
    "not_needed" => "Not needed"
  }.freeze

  belongs_to :planned_meal, inverse_of: :planned_meal_ingredients
  belongs_to :source_recipe, class_name: "Recipe", optional: true, inverse_of: :planned_meal_ingredients
  belongs_to :source_recipe_ingredient, class_name: "RecipeIngredient", optional: true, inverse_of: :planned_meal_ingredients
  belongs_to :ingredient, inverse_of: :planned_meal_ingredients
  belongs_to :replacement_ingredient, class_name: "Ingredient", optional: true, inverse_of: :replacement_planned_meal_ingredients
  has_many :pantry_consumptions, dependent: :restrict_with_exception, inverse_of: :planned_meal_ingredient

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
  # The requirements a person may answer: a current row of a plan their own
  # household shares with them. Household ownership and person visibility are one
  # question, so every review endpoint asks it in one place rather than
  # reassembling the join and risking a surface that scopes only half of it.
  scope :reviewable_by, ->(household, person) {
    active.joins(:planned_meal).merge(household.planned_meals.visible_to(person))
  }

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

  # The scaled amount this requirement actually asks the household for, and the
  # replacement's once a substitution redirected it. Unit semantics always travel
  # as a Measurement so nothing compares stored unit strings directly.
  def measurement
    Ingredient::Measurement.new(quantity: quantity, unit: unit)
  end

  def replacement_measurement
    Ingredient::Measurement.new(quantity: replacement_quantity, unit: replacement_unit)
  end

  def active?
    superseded_at.nil?
  end

  # The decision that actually has to resolve. A substitution redirects the
  # requirement at the replacement the household chose, so the replacement's
  # decision is the one allocation and shopping both answer to.
  def effective_decision
    substituted? ? replacement_decision : decision
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

  # Choosing a replacement is a review answer like any other, so it is refused
  # once the plan has been cooked and its decisions became history.
  def substitute!(ingredient:, display_quantity: nil, unit: nil, display_name: nil, at: Time.current)
    measurement = Ingredient::Measurement.new(quantity: display_quantity, unit: unit)
    planned_meal.with_open_review do
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
  end

  def decide_replacement!(decision, at: Time.current)
    update!(replacement_decision: decision, decided_at: at)
  end

  # The household answering this requirement in the review, and the only path the
  # review's row actions take.
  #
  # Deciding "on hand" is itself a pantry confirmation: the contract defines the
  # decision as evidence the household confirmed, so recording the decision alone
  # would leave the household's own assertion contradicted by the very next
  # allocation pass. The evidence is ensured rather than drawn — it rises to what
  # this requirement needs and never falls — so readiness still consumes nothing.
  # The other decisions record a decision and write no evidence.
  def answer!(decision, by:, at: Time.current)
    planned_meal.with_open_review do
      ensure_pantry_evidence(ingredient, measurement, by: by, at: at) if decision.to_s == "on_hand"
      decide!(decision, at: at)
    end
    self
  end

  # The replacement is the ingredient allocation actually draws on once a
  # requirement is substituted, so its answer carries the same evidence.
  def answer_replacement!(decision, by:, at: Time.current)
    planned_meal.with_open_review do
      ensure_pantry_evidence(replacement_ingredient, replacement_measurement, by: by, at: at) if decision.to_s == "on_hand"
      decide_replacement!(decision, at: at)
    end
    self
  end

  # Whether the replacement's own decision is the one still open. Both the
  # rendered controls and the endpoint ask this same question of the record.
  def replacement_resolvable?
    active? && substituted? && replacement_ingredient.present?
  end

  def decision_label
    DECISION_LABELS.fetch(decision)
  end

  def replacement_decision_label
    DECISION_LABELS.fetch(replacement_decision) if replacement_decision
  end

  def supersede!(reason, at: Time.current)
    update!(superseded_at: at, superseded_reason: reason)
  end

  # Obsolete requirements leave the active set: resolved ones stay as immutable
  # provenance, untouched ones simply disappear. A requirement that drew pantry
  # stock is provenance too — the consumption ledger stamps it as the requirement
  # that was answered at cooking time, and that claim is never rewritten.
  def discard_or_supersede!(reason, at: Time.current)
    resolved? || drew_pantry_stock? ? supersede!(reason, at: at) : destroy!
  end

  def drew_pantry_stock?
    pantry_consumptions.exists?
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
    # Two requirements carry no amount to confirm: a free-text one such as "salt to
    # taste", which stays source-specific and faithful rather than being coerced to
    # a number, and — inside ensure_at_least! — a confirmed row in an incompatible
    # family. Both record the decision and write nothing, because inventing or
    # overwriting a household observation is worse than an unexplained row.
    def ensure_pantry_evidence(ingredient, measurement, by:, at:)
      return unless measurement.known?

      PantryItem.for(household: planned_meal.household, ingredient: ingredient).ensure_at_least!(
        quantity: measurement.quantity,
        unit: measurement.normalized_label,
        source: PantryItem::READINESS_REVIEW_SOURCE,
        confirmed_by: by,
        confirmed_at: at
      )
    end

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
