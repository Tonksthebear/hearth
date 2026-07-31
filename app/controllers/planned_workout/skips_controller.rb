class PlannedWorkout::SkipsController < ApplicationController
  before_action :set_planned_workout

  def create
    @planned_workout.skip!(reason: skip_params[:skip_reason])
    redirect_to activity_week_path(date: @planned_workout.scheduled_on), notice: "Workout skipped.", status: :see_other
  rescue ActiveRecord::RecordInvalid
    redirect_to activity_week_path(date: @planned_workout.scheduled_on),
      alert: @planned_workout.errors.full_messages.to_sentence,
      status: :see_other
  end

  def destroy
    @planned_workout.restore!
    redirect_to activity_week_path(date: @planned_workout.scheduled_on), notice: "Workout restored to the plan.", status: :see_other
  rescue ActiveRecord::RecordInvalid
    redirect_to activity_week_path(date: @planned_workout.scheduled_on),
      alert: @planned_workout.errors.full_messages.to_sentence,
      status: :see_other
  end

  private
    def set_planned_workout
      @planned_workout = Current.person.planned_workouts.find(params[:planned_workout_id])
    end

    def skip_params
      params.fetch(:planned_workout, {}).permit(:skip_reason)
    end
end
