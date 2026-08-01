class PlannedMeal::MealsController < ApplicationController
  def create
    planned_meal = Current.household.planned_meals.visible_to(Current.person).find(params[:planned_meal_id])
    meal = planned_meal.convert_for!(Current.person)

    redirect_to meal, notice: "#{meal.description} was logged for #{Current.person.name}.", status: :see_other
  rescue ActiveRecord::RecordInvalid
    redirect_to meal_week_path(date: planned_meal.planned_on),
      alert: "That plan can no longer be logged.",
      status: :see_other
  end
end
