class ShoppingListItemSource < ApplicationRecord
  # What the household knows about the requirement behind one contributing meal.
  # A deficit only exists once the requirement resolved, so an effective decision
  # that is still `unknown` can only have been resolved by definitive pantry
  # evidence. `not_needed` never demands anything and `substituted` is never an
  # effective decision, so neither reaches this vocabulary.
  CONFIRMATION_LABELS = {
    missing: "Missing",
    on_hand: "On hand",
    pantry_evidence: "From pantry evidence"
  }.freeze

  belongs_to :shopping_list_item, inverse_of: :shopping_list_item_sources
  belongs_to :planned_meal_ingredient
  has_one :planned_meal, through: :planned_meal_ingredient

  delegate :substituted?, :replacement_display_name, to: :planned_meal_ingredient

  validates :planned_meal_ingredient_id, uniqueness: true

  def confirmation_state
    case planned_meal_ingredient.effective_decision
    when "missing" then :missing
    when "on_hand" then :on_hand
    else :pantry_evidence
    end
  end

  # Whether the household itself resolved this requirement, rather than the
  # pantry resolving it on their behalf.
  def household_confirmed?
    confirmation_state != :pantry_evidence
  end

  def confirmation_label
    CONFIRMATION_LABELS.fetch(confirmation_state)
  end
end
