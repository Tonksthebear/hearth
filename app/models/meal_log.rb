class MealLog < ApplicationRecord
  belongs_to :household
  belongs_to :person
  belongs_to :recipe, optional: true

  scope :during, ->(date_range) { where(eaten_on: date_range) }

  validates :eaten_on, presence: true
  validate :recipe_or_ad_hoc_description
  validate :person_belongs_to_household
  validate :recipe_belongs_to_household
  validate :recipe_reference_is_available

  attr_accessor :invalid_recipe_reference

  class << self
    def build_for(household:, person:, eaten_on:, recipe_id: nil, ad_hoc_description: nil)
      new(
        household: household,
        person: person,
        eaten_on: eaten_on,
        recipe: recipe_id.present? ? household.recipes.find_by(id: recipe_id) : nil,
        ad_hoc_description: ad_hoc_description,
        invalid_recipe_reference: recipe_id.present? && !household.recipes.exists?(id: recipe_id)
      )
    end
  end

  def description
    recipe&.title || ad_hoc_description
  end

  private
    def recipe_or_ad_hoc_description
      if recipe.present? == ad_hoc_description.present?
        errors.add(:base, "Choose a recipe or describe an ad hoc meal, but not both.")
      end
    end

    def person_belongs_to_household
      errors.add(:person, "must belong to this household") if person && person.household != household
    end

    def recipe_belongs_to_household
      errors.add(:recipe, "must belong to this household") if recipe && recipe.household != household
    end

    def recipe_reference_is_available
      errors.add(:recipe, "is not available") if invalid_recipe_reference
    end
end
