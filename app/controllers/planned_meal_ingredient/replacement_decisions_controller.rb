class PlannedMealIngredient::ReplacementDecisionsController < ApplicationController
  # A substitution never chains, so the replacement resolves to on hand or
  # missing only.
  DECISIONS = %w[ on_hand missing ].freeze

  before_action :set_requirement

  def update
    decision = params.expect(:replacement_decision)
    raise ActiveRecord::RecordNotFound unless DECISIONS.include?(decision)

    @requirement.answer_replacement!(decision, by: Current.person)

    redirect_to planned_meal_ingredient_review_path(@requirement.planned_meal), status: :see_other
  end

  private
    # replacement_resolvable? decides whether this endpoint applies to the row at
    # all; whether the review is still open is decided inside answer_replacement!,
    # under the plan's lock, so cooking cannot commit between check and write.
    def set_requirement
      @requirement = PlannedMealIngredient.reviewable_by(Current.household, Current.person).find(params[:planned_meal_ingredient_id])
      raise ActiveRecord::RecordNotFound unless @requirement.replacement_resolvable?
    end
end
