class PlannedMeal::IngredientReviewsController < ApplicationController
  def show
    @planned_meal = Current.household.planned_meals.visible_to(Current.person).find(params[:planned_meal_id])
    @ingredient_review = PlannedMeal::IngredientReview.new(planned_meal: @planned_meal, person: Current.person)
    @meal_week = MealWeek.for(household: Current.household, person: Current.person, date: @planned_meal.planned_on)
  end
end
