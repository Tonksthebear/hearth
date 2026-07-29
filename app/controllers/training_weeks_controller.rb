class TrainingWeeksController < ApplicationController
  def show
    @training_week = TrainingWeek.for(
      household: Current.household,
      person: Current.person,
      date: params[:date]
    )
    @workout_templates = Current.household.workout_templates.order(:title)
  end
end
