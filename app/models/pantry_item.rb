class PantryItem < ApplicationRecord
  # Pantry rows store Ingredient::Measurement's canonical normalized label. That
  # label is the only one the measurement PORO does not also accept as an authored
  # alias, so it round-trips through the blank unit the PORO reads as generic count.
  GENERIC_COUNT_UNIT = Ingredient::Measurement::GENERIC_COUNT.normalized_label
  PURCHASE_SOURCE = "purchase".freeze

  belongs_to :household
  belongs_to :ingredient
  belongs_to :confirmed_by, class_name: "Person", inverse_of: :confirmed_pantry_items

  enum :state, {
    confirmed: "confirmed",
    low: "low",
    out: "out",
    unknown: "unknown"
  }, validate: true

  validates :confirmation_source, presence: true
  validates :confirmed_at, presence: true
  validates :ingredient_id, uniqueness: { scope: :household_id }
  validate :ingredient_belongs_to_household
  validate :confirmer_belongs_to_household
  validate :amount_matches_state

  class << self
    # The household's current pantry row for a canonical ingredient. An untracked
    # ingredient returns an unsaved unknown row, because absence is functionally
    # unknown and the catalog is not backfilled with unknown rows. That row stays
    # detached from household.pantry_items: it cannot be valid until a command
    # supplies provenance, so autosaving it with the household would fail.
    def for(household:, ingredient:)
      household.pantry_items.find_by(ingredient: ingredient) ||
        new(household: household, ingredient: ingredient, state: :unknown)
    end
  end

  def quantity
    return unless quantity_numerator && quantity_denominator&.positive?

    Rational(quantity_numerator, quantity_denominator)
  end

  def measurement
    Ingredient::Measurement.new(quantity: quantity, unit: measurement_unit(unit))
  end

  # Exact quantity later allocation may draw on. An out row supplies zero; low and
  # unknown stay unresolved and supply nothing.
  def available_quantity
    return Rational(0) if out?

    quantity
  end

  def confirm!(quantity:, unit: nil, source:, confirmed_by:, confirmed_at: Time.current)
    confirmed = Ingredient::Measurement.new(quantity: quantity, unit: measurement_unit(unit))

    unless confirmed.known? && confirmed.quantity.positive?
      errors.add(:base, "Confirmed pantry inventory needs an exact positive amount in a recognized unit.")
      raise ActiveRecord::RecordInvalid, self
    end

    observe!(
      state: :confirmed,
      quantity: confirmed.quantity,
      unit: confirmed.normalized_label,
      source: source,
      confirmed_by: confirmed_by,
      confirmed_at: confirmed_at
    )
  end

  # Applies a signed exact change to confirmed inventory. Ingredient::Measurement
  # stays unsigned: its absolute magnitude is what gets classified and converted,
  # and the sign is applied here.
  def adjust!(delta:, unit: nil, source:, confirmed_by:, confirmed_at: Time.current)
    raise ArgumentError, "Pantry adjustments need an exact Rational delta" unless delta.is_a?(Rational)

    unless persisted?
      errors.add(:base, "Only confirmed pantry inventory can be adjusted.")
      raise ActiveRecord::RecordInvalid, self
    end

    with_lock do
      # Recompute from the row this transaction reloaded, never from a stale copy.
      # SQLite drops FOR UPDATE, so this guarantees no silent stale overwrite
      # rather than a held row lock.
      unless confirmed?
        errors.add(:base, "Only confirmed pantry inventory can be adjusted.")
        raise ActiveRecord::RecordInvalid, self
      end

      change = Ingredient::Measurement.new(quantity: delta.abs, unit: measurement_unit(unit))
      converted = change.convert_to(measurement_unit(self.unit)) if change.known?

      if converted.nil?
        errors.add(:base, "A pantry adjustment needs a recognized unit compatible with the confirmed amount.")
        raise ActiveRecord::RecordInvalid, self
      end

      adjusted = quantity + (delta.negative? ? -converted : converted)

      if adjusted.negative?
        errors.add(:base, "A pantry adjustment cannot take inventory below zero.")
        raise ActiveRecord::RecordInvalid, self
      end

      if adjusted.zero?
        observe!(state: :out, source: source, confirmed_by: confirmed_by, confirmed_at: confirmed_at)
      else
        observe!(
          state: :confirmed,
          quantity: adjusted,
          unit: self.unit,
          source: source,
          confirmed_by: confirmed_by,
          confirmed_at: confirmed_at
        )
      end
    end
  end

  # What the household actually brought home. Confirmed inventory in a compatible
  # unit grows by the purchased amount, while low, out, unknown, and untracked
  # rows are re-established through confirmation rather than adjusted. Buying
  # something you had none of is the common case, so it must not raise.
  def record_purchase!(quantity:, unit: nil, confirmed_by:, confirmed_at: Time.current)
    purchased = Ingredient::Measurement.new(quantity: quantity, unit: measurement_unit(unit))

    unless purchased.known? && purchased.quantity.positive?
      errors.add(:base, "A purchase needs an exact positive amount in a recognized unit.")
      raise ActiveRecord::RecordInvalid, self
    end

    if persisted? && confirmed?
      adjust!(delta: purchased.quantity, unit: unit, source: PURCHASE_SOURCE, confirmed_by: confirmed_by, confirmed_at: confirmed_at)
    else
      confirm!(quantity: quantity, unit: unit, source: PURCHASE_SOURCE, confirmed_by: confirmed_by, confirmed_at: confirmed_at)
    end
  end

  def mark_low!(source:, confirmed_by:, confirmed_at: Time.current)
    observe!(state: :low, source: source, confirmed_by: confirmed_by, confirmed_at: confirmed_at)
  end

  def mark_out!(source:, confirmed_by:, confirmed_at: Time.current)
    observe!(state: :out, source: source, confirmed_by: confirmed_by, confirmed_at: confirmed_at)
  end

  # Persists unknown so the last action stays visible. An untracked ingredient is
  # already unknown, so clearing it is a no-op rather than a new catalog row.
  def clear!(source:, confirmed_by:, confirmed_at: Time.current)
    return false unless persisted?

    observe!(state: :unknown, source: source, confirmed_by: confirmed_by, confirmed_at: confirmed_at)
  end

  protected
    def observe!(state:, source:, confirmed_by:, confirmed_at:, quantity: nil, unit: nil)
      assign_attributes(
        state: state,
        quantity_numerator: quantity&.numerator,
        quantity_denominator: quantity&.denominator,
        unit: unit,
        confirmation_source: source,
        confirmed_by: confirmed_by,
        confirmed_at: confirmed_at
      )
      save!
      self
    rescue ActiveRecord::RecordNotUnique
      raise if persisted?

      # The unique index owns household and ingredient identity. Another writer won
      # the create race, so the same observation applies to the winning row.
      household.pantry_items.find_by!(ingredient_id: ingredient_id).observe!(
        state: state,
        source: source,
        confirmed_by: confirmed_by,
        confirmed_at: confirmed_at,
        quantity: quantity,
        unit: unit
      )
    end

  private
    def measurement_unit(value)
      value.to_s.squish.casecmp?(GENERIC_COUNT_UNIT) ? nil : value
    end

    # The canonical label the stored unit must already be, or nil when the stored
    # unit is not a recognized measurement at all. The database can only require a
    # unit to be present, so recognition lives here.
    def canonical_unit_label
      Ingredient::Measurement.new(quantity: 1, unit: measurement_unit(unit)).normalized_label
    end

    def ingredient_belongs_to_household
      return if ingredient.blank? || ingredient.household_id == household_id

      errors.add(:ingredient, "must belong to this household")
    end

    def confirmer_belongs_to_household
      return if confirmed_by.blank? || confirmed_by.household_id == household_id

      errors.add(:confirmed_by, "must belong to this household")
    end

    def amount_matches_state
      return unless self.class.states.key?(state)

      if confirmed?
        errors.add(:quantity, "must be an exact positive amount") unless quantity&.positive?
        errors.add(:unit, "must be a recognized canonical unit") unless unit.present? && unit == canonical_unit_label
      elsif quantity_numerator.present? || quantity_denominator.present? || unit.present?
        errors.add(:quantity, "belongs only to confirmed pantry inventory")
      end
    end
end
