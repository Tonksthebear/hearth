class ExercisesController < ApplicationController
  before_action :set_exercise, only: %i[ show edit update ]
  before_action :prepare_form, only: %i[ new create edit update ]

  def index
    @exercises = Current.household.exercises.order(:name)
  end

  def show
  end

  def new
    @exercise = Current.household.exercises.build
  end

  def create
    @exercise = Current.household.exercises.build(exercise_params)

    if @exercise.save
      redirect_to @exercise, notice: "#{@exercise.name} was created.", status: :see_other
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @exercise.update(exercise_params)
      redirect_to @exercise, notice: "#{@exercise.name} was updated.", status: :see_other
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private
    def set_exercise
      @exercise = Current.household.exercises.find(params[:id])
    end

    def prepare_form
      @modalities = Exercise::MODALITIES
      @movement_patterns = Exercise::MOVEMENT_PATTERNS
    end

    def exercise_params
      params.fetch(:exercise).permit(:name, :modality, :movement_pattern, :equipment, :guidance)
    end
end
