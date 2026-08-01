class ShoppingListItem < ApplicationRecord
  belongs_to :shopping_list
  belongs_to :ingredient, optional: true
  has_many :shopping_list_item_sources,
    -> { joins(:planned_meal, :recipe_ingredient).order("planned_meals.planned_on", "planned_meals.id", "recipe_ingredients.position", "recipe_ingredients.id") },
    dependent: :destroy,
    inverse_of: :shopping_list_item
  has_many :planned_meals, through: :shopping_list_item_sources

  validates :name, presence: true

  scope :unchecked, -> { where(completed_at: nil) }

  def completed?
    completed_at.present?
  end

  def user_managed?
    user_managed_at.present?
  end

  def manual?
    generated_key.blank?
  end

  def removable_by_person?
    manual? || (user_managed? && shopping_list_item_sources.empty?)
  end

  def complete!
    update!(completed_at: completed_at || Time.current)
  end

  def uncomplete!
    update!(completed_at: nil)
  end

  def apply_user_attributes(attributes)
    assign_attributes(attributes)
    self.user_managed_at ||= Time.current if changed?
    save
  end

  def reconcile_sources!(sources)
    desired = sources.index_by { |source| [ source.planned_meal.id, source.recipe_ingredient.id ] }
    existing = shopping_list_item_sources.index_by { |source| [ source.planned_meal_id, source.recipe_ingredient_id ] }

    (existing.keys - desired.keys).each { |key| existing.fetch(key).destroy! }
    (desired.keys - existing.keys).each do |key|
      source = desired.fetch(key)
      shopping_list_item_sources.create!(
        planned_meal: source.planned_meal,
        recipe_ingredient: source.recipe_ingredient
      )
    end
  end
end
