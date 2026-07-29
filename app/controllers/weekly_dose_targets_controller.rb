class WeeklyDoseTargetsController < ApplicationController
  def update
    if Current.person.update(target_params)
      redirect_to training_week_path(date: params[:date]), notice: "Weekly targets updated.", status: :see_other
    else
      @training_week = TrainingWeek.for(
        household: Current.household,
        person: Current.person,
        date: params[:date]
      )
      @workout_templates = Current.household.workout_templates.order(:title)
      render "training_weeks/show", status: :unprocessable_entity
    end
  end

  private
    def target_params
      params.fetch(:person).permit(
        :weekly_structured_minutes_target,
        :weekly_strength_sessions_target,
        :weekly_zone2_minutes_target,
        :weekly_vigorous_minutes_target
      )
    end
end
