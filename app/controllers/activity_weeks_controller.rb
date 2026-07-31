class ActivityWeeksController < ApplicationController
  def show
    prepare_week
  end

  private
    def prepare_week
      @activity_week = ActivityWeek.for(
        household: Current.household,
        person: Current.person,
        date: params[:date]
      )
      @planned_workout = Current.person.planned_workouts.new(
        household: Current.household,
        scheduled_on: @activity_week.includes_today? ? Date.current : @activity_week.start_date
      )
      @workout_template_options = Current.household.workout_templates.order(:title).map { |template| [ template.title, template.id ] }
    end
end
