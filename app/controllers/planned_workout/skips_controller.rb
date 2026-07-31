class PlannedWorkout::SkipsController < ApplicationController
  before_action :set_planned_workout

  def create
    @planned_workout.skip!(reason: skip_params[:skip_reason])
    redirect_to redirect_path, notice: "Workout skipped.", status: :see_other
  rescue ActiveRecord::RecordInvalid
    redirect_to redirect_path,
      alert: @planned_workout.errors.full_messages.to_sentence,
      status: :see_other
  end

  def destroy
    @planned_workout.restore!
    redirect_to redirect_path, notice: "Workout restored to the plan.", status: :see_other
  rescue ActiveRecord::RecordInvalid
    redirect_to redirect_path,
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

    def redirect_path
      params[:return_to] == "today" ? root_path : activity_week_path(date: @planned_workout.scheduled_on)
    end
end
