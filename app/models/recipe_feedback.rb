class RecipeFeedback < ApplicationRecord
  belongs_to :meal_item, inverse_of: :recipe_feedback

  validates :body, presence: true
  validate :meal_item_is_recipe_backed

  delegate :meal, :recipe, to: :meal_item
  delegate :person, :eaten_on, to: :meal

  private
    def meal_item_is_recipe_backed
      errors.add(:meal_item, "must reference a recipe") unless meal_item&.recipe?
    end
end
