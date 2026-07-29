class RecipeInstruction < ApplicationRecord
  belongs_to :recipe

  validates :body, presence: true
  validates :position,
    presence: true,
    numericality: { only_integer: true, greater_than: 0 },
    uniqueness: { scope: :recipe_id }
end
