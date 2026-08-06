class PlannedMealIngredient::ReplacementDecisionsController < ApplicationController
  # A substitution never chains, so the replacement resolves to on hand or
  # missing only.
  DECISIONS = %w[ on_hand missing ].freeze

  before_action :set_requirement

  def update
    decision = params.expect(:replacement_decision)
    raise ActiveRecord::RecordNotFound unless DECISIONS.include?(decision)

    if decision == "on_hand"
      @requirement.confirm_replacement_on_hand!(by: Current.person)
    else
      @requirement.decide_replacement!(decision)
    end

    redirect_to planned_meal_ingredient_review_path(@requirement.planned_meal), status: :see_other
  end

  private
    def set_requirement
      @requirement = PlannedMealIngredient.reviewable_by(Current.household, Current.person).find(params[:planned_meal_ingredient_id])
      raise ActiveRecord::RecordNotFound unless @requirement.planned_meal.ingredient_review_open? && @requirement.replacement_resolvable?
    end
end
