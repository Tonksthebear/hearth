class RecipeInstruction < ApplicationRecord
  DURATION_UNITS = %w[seconds minutes hours].freeze
  TEMPERATURE_UNITS = %w[F C].freeze

  belongs_to :recipe
  has_many :recipe_instruction_ingredients, -> { order(:position) }, dependent: :destroy
  has_many :referenced_recipe_ingredients,
    through: :recipe_instruction_ingredients,
    source: :recipe_ingredient

  normalizes :duration_unit, :temperature_unit, with: ->(unit) { unit.presence }

  validates :body, presence: true
  validates :position,
    presence: true,
    numericality: { only_integer: true, greater_than: 0 }
  validates :duration_amount, numericality: { greater_than: 0 }, allow_nil: true
  validates :duration_unit, inclusion: { in: DURATION_UNITS }, allow_blank: true
  validates :temperature_unit, inclusion: { in: TEMPERATURE_UNITS }, allow_blank: true
  validate :duration_pair_is_complete
  validate :temperature_pair_is_complete

  def ingredient_reference_keys
    return @ingredient_reference_keys if defined?(@ingredient_reference_keys)

    referenced_recipe_ingredients.map(&:form_key)
  end

  def ingredient_reference_keys=(keys)
    @ingredient_reference_keys = Array(keys).filter_map { |key| key.to_s.presence }
    @ingredient_reference_keys_assigned = true
  end

  def ingredient_reference_keys_assigned?
    @ingredient_reference_keys_assigned
  end

  def duration_cue
    "#{formatted_amount(duration_amount)} #{duration_unit}" if duration_amount.present?
  end

  def temperature_cue
    "#{formatted_amount(temperature_amount)}°#{temperature_unit}" if temperature_amount.present?
  end

  private
    def duration_pair_is_complete
      validate_pair(:duration_amount, :duration_unit)
    end

    def temperature_pair_is_complete
      validate_pair(:temperature_amount, :temperature_unit)
    end

    def validate_pair(amount_attribute, unit_attribute)
      amount = public_send(amount_attribute)
      unit = public_send(unit_attribute)
      return if amount.present? == unit.present?

      errors.add(amount.present? ? unit_attribute : amount_attribute, "must be provided with its #{amount_attribute.to_s.delete_suffix('_amount').humanize.downcase}")
    end

    def formatted_amount(amount)
      amount.to_s("F").sub(/\.0+\z/, "").sub(/(\.\d*?)0+\z/, "\\1")
    end
end
