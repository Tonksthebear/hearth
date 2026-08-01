class IngredientNutrientValue < ApplicationRecord
  belongs_to :ingredient
  belongs_to :nutrient

  validates :nutrient_id, uniqueness: { scope: :ingredient_id }
  validates :amount_per_100_grams, numericality: { greater_than_or_equal_to: 0 }
end
