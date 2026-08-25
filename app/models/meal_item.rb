class MealItem < ApplicationRecord
  belongs_to :meal, inverse_of: :meal_items
  belongs_to :recipe, optional: true
  belongs_to :ingredient, optional: true
  has_one :recipe_feedback, dependent: :destroy, inverse_of: :meal_item
  has_many :meal_item_nutrient_values, -> { order(:id) }, dependent: :destroy, inverse_of: :meal_item

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

  before_validation :remove_blank_recipe_feedback, prepend: true
  before_validation :capture_snapshot_label
  # Nutrition is historical: upstream recipe or ingredient edits do not rewrite what was recorded at mealtime.
  after_save :refresh_nutrition_snapshot, if: :nutrition_snapshot_refresh_required?

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

  def nutrition_status
    return "complete" if nutrition_complete? && !nutrition_estimated?
    return "estimated" if nutrition_complete? && nutrition_estimated?
    return "incomplete — portion needed" if (recipe? || ingredient?) && portion_amount.blank?
    return "incomplete" if meal_item_nutrient_values.any?

    "unavailable"
  end

  private
    def nutrition_snapshot_refresh_required?
      previously_new_record? || saved_change_to_source_kind? || saved_change_to_recipe_id? ||
        saved_change_to_ingredient_id? || saved_change_to_portion_amount? || saved_change_to_portion_unit?
    end

    def refresh_nutrition_snapshot
      values, complete = nutrition_snapshot_values
      meal_item_nutrient_values.delete_all
      values.each do |value|
        meal_item_nutrient_values.create!(
          nutrient: value.fetch(:nutrient),
          amount: value.fetch(:amount).round(6, BigDecimal::ROUND_HALF_UP),
          snapshot_key: value.fetch(:nutrient).key,
          snapshot_name: value.fetch(:nutrient).name,
          snapshot_unit: value.fetch(:nutrient).unit,
          snapshot_source_name: value[:source_name],
          snapshot_provenance_status: value[:provenance_status],
          snapshot_calculation_kind: value.fetch(:calculation_kind)
        )
      end
      estimated = values.any? { |value| value.fetch(:calculation_kind) == "estimated" }
      update_columns(nutrition_complete: complete, nutrition_estimated: estimated)
      self.nutrition_complete = complete
      self.nutrition_estimated = estimated
    end

    def nutrition_snapshot_values
      return [ [], false ] if portion_amount.blank?

      if recipe? && serving_portion?
        results = Recipe::Nutrition.new(recipe).results
        values = results.filter_map do |result|
          next unless result.amount

          {
            nutrient: result.nutrient,
            amount: result.amount * BigDecimal(portion_amount.to_s),
            source_name: result.source_name,
            provenance_status: result.provenance_status,
            calculation_kind: "estimated"
          }
        end
        [ values, results.all?(&:complete) ]
      elsif ingredient? && gram_portion?
        values = ingredient.ingredient_nutrient_values.map do |value|
          {
            nutrient: value.nutrient,
            amount: BigDecimal(value.amount_per_100_grams.to_s) * BigDecimal(portion_amount.to_s) / 100,
            source_name: ingredient.nutrition_source_name,
            provenance_status: ingredient.nutrition_provenance_status,
            calculation_kind: "explicit"
          }
        end
        [ values, values.length == Nutrient.count ]
      else
        [ [], false ]
      end
    end

    def serving_portion?
      %w[serving servings].include?(portion_unit.to_s.squish.downcase)
    end

    def gram_portion?
      %w[g gram grams].include?(portion_unit.to_s.squish.downcase)
    end

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

    def remove_blank_recipe_feedback
      recipe_feedback.mark_for_destruction if recipe_feedback&.persisted? && recipe_feedback.body.blank?
    end
end
