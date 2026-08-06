class PlannedMealIngredient::DecisionsController < ApplicationController
  # The three decisions this endpoint records directly. Substituting is its own
  # flow because it collects a replacement, and unknown is the state a
  # requirement starts in rather than something the household chooses.
  DECISIONS = %w[ on_hand missing not_needed ].freeze

  before_action :set_requirement

  def update
    decision = params.expect(:decision)
    raise ActiveRecord::RecordNotFound unless DECISIONS.include?(decision)

    # "On hand" also writes the pantry evidence the decision asserts; the other
    # two record a decision and nothing else.
    if decision == "on_hand"
      @requirement.confirm_on_hand!(by: Current.person)
    else
      @requirement.decide!(decision)
    end

    redirect_to planned_meal_ingredient_review_path(@requirement.planned_meal), status: :see_other
  end

  private
    def set_requirement
      @requirement = PlannedMealIngredient.reviewable_by(Current.household, Current.person).find(params[:planned_meal_ingredient_id])
      raise ActiveRecord::RecordNotFound unless @requirement.planned_meal.ingredient_review_open?
    end
end
