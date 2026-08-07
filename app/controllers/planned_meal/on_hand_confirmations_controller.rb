class PlannedMeal::OnHandConfirmationsController < ApplicationController
  def create
    planned_meal = Current.household.planned_meals.visible_to(Current.person).find(params[:planned_meal_id])
    # Whether anything is left to answer; the lifecycle half is rechecked inside
    # mark_remaining_ingredients_on_hand!, under the plan's lock.
    raise ActiveRecord::RecordNotFound unless planned_meal.ingredients_awaiting_review?

    planned_meal.mark_remaining_ingredients_on_hand!(by: Current.person)

    redirect_to planned_meal_ingredient_review_path(planned_meal),
      notice: "Everything still unanswered is now on hand.",
      status: :see_other
  end
end
