class HabitsController < ApplicationController
  before_action :set_habit, only: %i[ edit update ]
  before_action :prepare_form, only: %i[ new create edit update ]

  def index
    @habits = Current.household.habits.includes(:habit_metrics).order(:name)
    @person_habits_by_habit_id = Current.person.person_habits.index_by(&:habit_id)
  end

  def new
    @habit = Current.household.habits.build
    @habit.add_metric
  end

  def create
    @habit = Current.household.habits.build(habit_params)
    @habit.normalize_positions

    if structural_action?
      render_form_update
    elsif @habit.save
      redirect_to habits_path, notice: "#{@habit.name} was created.", status: :see_other
    else
      @habit.ensure_form_rows
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    @habit.assign_attributes(habit_params)
    @habit.normalize_positions

    if structural_action?
      render_form_update
    elsif @habit.save
      redirect_to habits_path, notice: "#{@habit.name} was updated.", status: :see_other
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private
    def set_habit
      @habit = Current.household.habits.find(params[:id])
    end

    def prepare_form
      @value_types = HabitMetric::VALUE_TYPES
    end

    def habit_params
      params.fetch(:habit).permit(
        :name,
        :description,
        habit_metrics_attributes: %i[ id key label value_type unit position _destroy ]
      )
    end

    def structural_action?
      if params[:add_metric]
        @habit.add_metric
      elsif params[:remove_metric]
        @habit.remove_metric(params[:remove_metric])
      elsif params[:move_metric]
        @habit.move_metric(params[:move_metric])
      end
    rescue ArgumentError => error
      @habit.errors.add(:base, error.message)
      true
    end

    def render_form_update
      render turbo_stream: turbo_stream.replace(
        "habit_form",
        partial: "habits/form",
        locals: { habit: @habit, value_types: @value_types }
      ), status: @habit.errors.any? ? :unprocessable_entity : :ok
    end
end
