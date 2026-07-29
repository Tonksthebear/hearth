class PersonHabitsController < ApplicationController
  before_action :set_person_habit, only: %i[ edit update ]

  def create
    habit = Current.household.habits.find(params.fetch(:habit_id))
    @person_habit = Current.person.person_habits.build(habit: habit, active: true)
    @person_habit.ensure_target_rows

    if @person_habit.save
      redirect_to edit_person_habit_path(@person_habit), notice: "#{habit.name} was activated.", status: :see_other
    else
      redirect_to habits_path, alert: @person_habit.errors.full_messages.to_sentence, status: :see_other
    end
  end

  def edit
    @person_habit.ensure_target_rows
  end

  def update
    @person_habit.assign_attributes(person_habit_params)
    @person_habit.ensure_target_rows

    if @person_habit.save
      redirect_to recovery_day_path, notice: "#{@person_habit.habit.name} was updated.", status: :see_other
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private
    def set_person_habit
      @person_habit = Current.person.person_habits
        .includes(habit: :habit_metrics)
        .find(params[:id])
    end

    def person_habit_params
      params.fetch(:person_habit).permit(
        :active,
        *PersonHabit::WEEKDAYS,
        person_habit_metrics_attributes: %i[
          id habit_metric_id number_value duration_value time_of_day_value boolean_value
        ]
      )
    end
end
