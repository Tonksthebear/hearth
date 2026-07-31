class PlannedMeal::MealsController < ApplicationController
  def create
    planned_meal = Current.household.planned_meals.visible_to(Current.person).find(params[:planned_meal_id])
    meal = planned_meal.convert_for!(Current.person)

    redirect_to meal, notice: "#{meal.description} was logged for #{Current.person.name}.", status: :see_other
  rescue ActiveRecord::RecordInvalid
    head :unprocessable_entity
  end
end
