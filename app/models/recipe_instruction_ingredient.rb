class RecipeInstructionIngredient < ApplicationRecord
  belongs_to :recipe
  belongs_to :recipe_instruction
  belongs_to :recipe_ingredient

  before_validation :assign_recipe

  validates :position,
    presence: true,
    numericality: { only_integer: true, greater_than: 0 }
  validate :records_belong_to_recipe

  private
    def assign_recipe
      self.recipe ||= recipe_instruction&.recipe
    end

    def records_belong_to_recipe
      return unless recipe && recipe_instruction && recipe_ingredient

      errors.add(:recipe_instruction, "must belong to the recipe") if recipe_instruction.recipe != recipe
      errors.add(:recipe_ingredient, "must belong to the recipe") if recipe_ingredient.recipe != recipe
    end
end
