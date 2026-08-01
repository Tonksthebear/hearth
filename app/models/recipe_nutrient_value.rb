class RecipeNutrientValue < ApplicationRecord
  belongs_to :recipe
  belongs_to :nutrient

  validates :nutrient_id, uniqueness: { scope: :recipe_id }
  validates :amount, numericality: { greater_than_or_equal_to: 0 }
end
