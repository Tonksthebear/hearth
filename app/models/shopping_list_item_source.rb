class ShoppingListItemSource < ApplicationRecord
  belongs_to :shopping_list_item, inverse_of: :shopping_list_item_sources
  belongs_to :planned_meal
  belongs_to :recipe_ingredient

  validates :planned_meal_id, uniqueness: { scope: :recipe_ingredient_id }
end
