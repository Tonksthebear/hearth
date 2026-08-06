class RecipeIngredient < ApplicationRecord
  belongs_to :recipe
  belongs_to :ingredient
  has_many :recipe_instruction_ingredients, dependent: :destroy
  has_many :recipe_instructions, through: :recipe_instruction_ingredients

  before_validation :resolve_ingredient
  before_validation :parse_display_quantity
  before_save :persist_ingredient

  validates :display_name, presence: true
  validates :position,
    presence: true,
    numericality: { only_integer: true, greater_than: 0 }
  validates :gram_weight, numericality: { greater_than: 0 }, allow_nil: true
  validate :ingredient_belongs_to_household

  def form_key
    @form_key ||= persisted? ? "ingredient-#{id}" : SecureRandom.uuid
  end

  def form_key=(value)
    @form_key = value.presence || SecureRandom.uuid
  end

  def quantity
    return unless quantity_numerator && quantity_denominator&.positive?

    Rational(quantity_numerator, quantity_denominator)
  end

  private
    def resolve_ingredient
      return if display_name.blank? || !recipe&.household

      self.ingredient = recipe.canonical_ingredient_for(display_name)
    end

    def parse_display_quantity
      measurement = Ingredient::Measurement.new(quantity: display_quantity, unit: unit)
      self.quantity_numerator = measurement.quantity&.numerator
      self.quantity_denominator = measurement.quantity&.denominator
    end

    def persist_ingredient
      return unless will_save_change_to_display_name? || ingredient_id.nil?

      self.ingredient = Ingredient.resolve!(household: recipe.household, name: display_name)
    end

    def ingredient_belongs_to_household
      return unless ingredient && recipe
      return if ingredient.household == recipe.household

      errors.add(:ingredient, "must belong to the recipe household")
    end
end
