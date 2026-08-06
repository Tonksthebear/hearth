class ShoppingListItem < ApplicationRecord
  belongs_to :shopping_list
  belongs_to :ingredient, optional: true
  has_many :shopping_list_item_sources,
    -> { joins(planned_meal_ingredient: :planned_meal).order("planned_meals.planned_on", "planned_meals.id", "planned_meal_ingredients.position", "planned_meal_ingredients.id") },
    dependent: :destroy,
    inverse_of: :shopping_list_item
  has_many :planned_meal_ingredients, through: :shopping_list_item_sources
  has_many :planned_meals, through: :planned_meal_ingredients

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

  # Purchase confirmation writes pantry evidence for a canonical ingredient, so a
  # manual row that names no ingredient has nothing to confirm against.
  def confirmable_into_pantry?
    ingredient_id.present?
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
    desired = sources.map(&:planned_meal_ingredient_id)
    existing = shopping_list_item_sources.index_by(&:planned_meal_ingredient_id)

    (existing.keys - desired).each { |key| existing.fetch(key).destroy! }
    (desired - existing.keys).each do |key|
      shopping_list_item_sources.create!(planned_meal_ingredient_id: key)
    end
  end
end
