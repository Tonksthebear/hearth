class Ingredient < ApplicationRecord
  belongs_to :household
  has_many :recipe_ingredients, dependent: :restrict_with_exception
  has_many :meal_items, dependent: :restrict_with_exception

  before_validation :normalize_identity

  validates :name, presence: true
  validates :normalized_name, presence: true, uniqueness: { scope: :household_id }

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
    def normalize_identity
      self.name = name.to_s.squish
      self.normalized_name = self.class.normalize_name(name)
    end
end
