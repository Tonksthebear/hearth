class Nutrient < ApplicationRecord
  DEFAULTS = [
    { key: "energy", name: "Energy", unit: "kcal", category: "energy", display_order: 1 },
    { key: "protein", name: "Protein", unit: "g", category: "macronutrient", display_order: 2 },
    { key: "carbohydrates", name: "Carbohydrates", unit: "g", category: "macronutrient", display_order: 3 },
    { key: "fat", name: "Fat", unit: "g", category: "macronutrient", display_order: 4 },
    { key: "fiber", name: "Fiber", unit: "g", category: "macronutrient", display_order: 5 },
    { key: "sodium", name: "Sodium", unit: "mg", category: "mineral", display_order: 6 }
  ].freeze

  has_many :ingredient_nutrient_values, dependent: :restrict_with_exception
  has_many :recipe_nutrient_values, dependent: :restrict_with_exception
  has_many :meal_item_nutrient_values, dependent: :nullify

  validates :key, :name, :unit, :category, presence: true
  validates :key, uniqueness: true
  validates :display_order, numericality: { only_integer: true, greater_than: 0 }, uniqueness: true
  validate :stable_identity, on: :update

  scope :displayed, -> { order(:display_order, :id) }

  class << self
    def ensure_defaults!
      transaction do
        DEFAULTS.each do |attributes|
          nutrient = find_or_initialize_by(key: attributes.fetch(:key))
          nutrient.assign_attributes(attributes)
          nutrient.save!
        end
      end
    end

    def format_amount(amount, unit:)
      return "—" if amount.nil?

      rounded = BigDecimal(amount.to_s).round(2, BigDecimal::ROUND_HALF_UP)
      number = rounded.to_s("F").sub(/\.0+\z/, "").sub(/(\.\d*?)0+\z/, "\\1")
      "#{number} #{unit}"
    end
  end

  private
    def stable_identity
      errors.add(:key, "cannot change") if will_save_change_to_key?
      errors.add(:unit, "cannot change") if will_save_change_to_unit?
    end
end
