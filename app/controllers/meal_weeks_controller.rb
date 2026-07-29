class MealWeeksController < ApplicationController
  def show
    @meal_week = MealWeek.for(
      household: Current.household,
      person: Current.person,
      date: params[:date]
    )
  end
end
