class MealItem < ApplicationRecord
  belongs_to :meal, inverse_of: :meal_items
  belongs_to :recipe, optional: true
  belongs_to :ingredient, optional: true
  has_one :recipe_feedback, dependent: :destroy, inverse_of: :meal_item

  accepts_nested_attributes_for :recipe_feedback, allow_destroy: true, reject_if: :all_blank

  enum :source_kind, {
    recipe: "recipe",
    ingredient: "ingredient",
    free_text: "free_text"
  }, validate: true

  validates :snapshot_label, presence: true
  validates :position, numericality: { only_integer: true, greater_than: 0 }
  validates :portion_amount, numericality: { greater_than: 0 }, allow_nil: true
  validate :exactly_one_source
  validate :source_belongs_to_household
  validate :feedback_requires_recipe

  before_validation :capture_snapshot_label

  attr_accessor :source_reference_invalid

  def source_id
    recipe_id || ingredient_id
  end

  def source=(record)
    self.recipe = record if record.is_a?(Recipe)
    self.ingredient = record if record.is_a?(Ingredient)
  end

  def portion
    [ portion_amount&.to_fs(:delimited), portion_unit ].compact_blank.join(" ")
  end

  private
    def capture_snapshot_label
      self.snapshot_label = recipe.title if recipe? && recipe && (snapshot_label.blank? || will_save_change_to_recipe_id?)
      self.snapshot_label = ingredient.name if ingredient? && ingredient && (snapshot_label.blank? || will_save_change_to_ingredient_id?)
      self.snapshot_label = snapshot_label.to_s.squish if free_text?
    end

    def exactly_one_source
      valid = (recipe? && recipe.present? && ingredient.nil?) ||
        (ingredient? && recipe.nil? && ingredient.present?) ||
        (free_text? && recipe.nil? && ingredient.nil?)
      errors.add(:base, "Choose exactly one recipe, ingredient, or free-text item.") unless valid
      errors.add(:base, "The selected item is not available.") if source_reference_invalid
    end

    def source_belongs_to_household
      household = meal&.household
      errors.add(:recipe, "must belong to this household") if recipe && recipe.household != household
      errors.add(:ingredient, "must belong to this household") if ingredient && ingredient.household != household
    end

    def feedback_requires_recipe
      return unless recipe_feedback && !recipe_feedback.marked_for_destruction?

      errors.add(:recipe_feedback, "is only available for recipe items") unless recipe?
    end
end
