class HabitCheckInsController < ApplicationController
  before_action :set_recovery_day

  def create
    person_habit = Current.person.person_habits.active.find(habit_check_in_params.fetch(:person_habit_id))
    @habit_check_in = person_habit.habit_check_ins.build(
      habit_check_in_params.except(:person_habit_id).merge(checked_on: @recovery_day.date)
    )

    persist_or_render
  end

  def update
    @habit_check_in = current_check_ins.find(params[:id])
    @habit_check_in.assign_attributes(habit_check_in_params.except(:person_habit_id))

    persist_or_render
  end

  def destroy
    current_check_ins.find(params[:id]).destroy!
    redirect_to redirect_path, notice: "Today's check-in was cleared.", status: :see_other
  end

  private
    def set_recovery_day
      @recovery_day = RecoveryDay.current(household: Current.household, person: Current.person)
    end

    def current_check_ins
      HabitCheckIn
        .joins(:person_habit)
        .where(person_habits: { person_id: Current.person.id }, checked_on: @recovery_day.date)
    end

    def habit_check_in_params
      params.fetch(:habit_check_in).permit(
        :person_habit_id,
        :notes,
        habit_check_in_measurements_attributes: %i[
          id habit_metric_id number_value duration_value time_of_day_value boolean_value
        ]
      )
    end

    def persist_or_render
      if @habit_check_in.save
        redirect_to redirect_path, notice: "Today's check-in was saved.", status: :see_other
      else
        @recovery_day = RecoveryDay.current(
          household: Current.household,
          person: Current.person,
          check_in: @habit_check_in
        )
        render "recovery_days/show", status: :unprocessable_entity
      end
    end

    def redirect_path
      case params[:return_to]
      when "today"
        root_path
      when "activity_week"
        activity_week_path(date: params[:date])
      else
        recovery_day_path
      end
    end
end
