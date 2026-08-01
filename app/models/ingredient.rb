class Ingredient < ApplicationRecord
  belongs_to :household
  has_many :recipe_ingredients, dependent: :restrict_with_exception
  has_many :meal_items, dependent: :restrict_with_exception
  has_many :ingredient_nutrient_values, -> { includes(:nutrient).order("nutrients.display_order") },
    dependent: :destroy,
    inverse_of: :ingredient

  accepts_nested_attributes_for :ingredient_nutrient_values,
    allow_destroy: true,
    reject_if: ->(attributes) { attributes["amount_per_100_grams"].blank? }

  enum :nutrition_provenance_status, {
    personal: "personal",
    verified: "verified",
    adapted: "adapted",
    observed: "observed"
  }, prefix: :nutrition, validate: { allow_nil: true }

  PROVENANCE_DESCRIPTIONS = {
    "personal" => "Created by your household.",
    "verified" => "Checked against the cited source.",
    "adapted" => "Intentionally changed from the cited source.",
    "observed" => "Recorded from practice without independent source verification."
  }.freeze

  before_validation :normalize_identity

  validates :name, presence: true
  validates :normalized_name, presence: true, uniqueness: { scope: :household_id }
  validates :nutrition_provenance_status, presence: true, if: :nutrition_profile_required?
  validates :nutrition_source_name, presence: true, if: :attributed_nutrition_profile?

  class << self
    def normalize_name(name)
      name.to_s.squish.downcase(:fold)
    end

    def for(household:, name:)
      normalized_name = normalize_name(name)
      household.ingredients.find_by(normalized_name:) || household.ingredients.build(
        name: name.to_s.squish,
        normalized_name:
      )
    end

    def resolve!(household:, name:)
      ingredient = self.for(household:, name:)
      ingredient.save! unless ingredient.persisted?
      ingredient
    rescue ActiveRecord::RecordNotUnique
      household.ingredients.find_by!(normalized_name: normalize_name(name))
    end
  end

  private
    def nutrition_profile_required?
      food_data_central_id.present? || nutrition_source_name.present? || ingredient_nutrient_values.reject(&:marked_for_destruction?).any?
    end

    def attributed_nutrition_profile?
      nutrition_profile_required? && nutrition_provenance_status.present? && !nutrition_personal?
    end

    def normalize_identity
      self.name = name.to_s.squish
      self.normalized_name = self.class.normalize_name(name)
    end
end
