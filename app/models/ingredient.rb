class Ingredient < ApplicationRecord
  NutritionCoverage = Data.define(:known_count, :total_count, :status) do
    def label
      case status
      when "complete" then "Complete"
      when "unavailable" then "No values"
      else "#{known_count} of #{total_count} known"
      end
    end
  end

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

  scope :matching, ->(query) {
    if query.present?
      pattern = "%#{sanitize_sql_like(Ingredient.normalize_name(query), "!")}%"
      where("normalized_name LIKE ? ESCAPE '!'", pattern)
    else
      all
    end
  }

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

  def nutrition_coverage(nutrients)
    nutrient_ids = nutrients.map(&:id)
    known_count = ingredient_nutrient_values.count do |value|
      nutrient_ids.include?(value.nutrient_id) && !value.amount_per_100_grams.nil?
    end
    status = if nutrient_ids.empty? || known_count.zero?
      "unavailable"
    elsif known_count == nutrient_ids.size
      "complete"
    else
      "incomplete"
    end

    NutritionCoverage.new(known_count:, total_count: nutrient_ids.size, status:)
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
