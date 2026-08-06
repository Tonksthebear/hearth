class PlannedMealIngredient::DecisionsController < ApplicationController
  # The three decisions this endpoint records directly. Substituting is its own
  # flow because it collects a replacement, and unknown is the state a
  # requirement starts in rather than something the household chooses.
  DECISIONS = %w[ on_hand missing not_needed ].freeze

  before_action :set_requirement

  def update
    decision = params.expect(:decision)
    raise ActiveRecord::RecordNotFound unless DECISIONS.include?(decision)

    @requirement.answer!(decision, by: Current.person)

    redirect_to planned_meal_ingredient_review_path(@requirement.planned_meal), status: :see_other
  end

  private
    # Ownership and visibility only. Whether the review is still open is decided
    # inside answer!, under the plan's lock, because checking it here would leave
    # a gap in which cooking could commit and the write would still land.
    def set_requirement
      @requirement = PlannedMealIngredient.reviewable_by(Current.household, Current.person).find(params[:planned_meal_ingredient_id])
    end
end
