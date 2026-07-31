class PlannedWorkoutsController < ApplicationController
  before_action :set_planned_workout, only: %i[ update destroy ]

  def create
    @planned_workout = Current.person.planned_workouts.new(planned_workout_params)
    @planned_workout.household = Current.household

    if @planned_workout.save
      redirect_to activity_week_path(date: @planned_workout.scheduled_on), notice: "Workout scheduled.", status: :see_other
    else
      prepare_week
      render "activity_weeks/show", status: :unprocessable_entity
    end
  end

  def update
    @planned_workout.reschedule!(scheduled_on: planned_workout_params[:scheduled_on])
    redirect_to activity_week_path(date: @planned_workout.scheduled_on), notice: "Workout rescheduled.", status: :see_other
  rescue ActiveRecord::RecordInvalid
    prepare_week
    render "activity_weeks/show", status: :unprocessable_entity
  end

  def destroy
    date = @planned_workout.scheduled_on
    if @planned_workout.destroy
      redirect_to activity_week_path(date: date), notice: "Workout removed from plan.", status: :see_other
    else
      redirect_to activity_week_path(date: date), alert: @planned_workout.errors.full_messages.to_sentence, status: :see_other
    end
  end

  private
    def set_planned_workout
      @planned_workout = Current.person.planned_workouts.find(params[:id])
    end

    def planned_workout_params
      params.expect(planned_workout: %i[ workout_template_id scheduled_on ])
    end

    def prepare_week
      @activity_week = ActivityWeek.for(
        household: Current.household,
        person: Current.person,
        date: @planned_workout.scheduled_on.presence || params[:date]
      )
      @workout_template_options = Current.household.workout_templates.order(:title).map { |template| [ template.title, template.id ] }
    end
end
