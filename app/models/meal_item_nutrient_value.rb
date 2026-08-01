class MealItemNutrientValue < ApplicationRecord
  belongs_to :meal_item
  belongs_to :nutrient, optional: true

  enum :snapshot_calculation_kind, { explicit: "explicit", estimated: "estimated" }, validate: true

  validates :snapshot_key, :snapshot_name, :snapshot_unit, presence: true
  validates :snapshot_key, uniqueness: { scope: :meal_item_id }
  validates :amount, numericality: { greater_than_or_equal_to: 0 }

  def formatted_amount
    Nutrient.format_amount(amount, unit: snapshot_unit)
  end
end
