class WorkoutTemplatesController < ApplicationController
  before_action :set_workout_template, only: %i[ show edit update ]
  before_action :prepare_form, only: %i[ new create edit update ]

  def index
    @workout_templates = Current.household.workout_templates.order(:title)
  end

  def show
    @workout_template.workout_blocks.includes(exercise_prescriptions: :exercise).load
  end

  def new
    @workout_template = Current.household.workout_templates.build(provenance_status: :personal)
    @workout_template.add_block
  end

  def create
    @workout_template = Current.household.workout_templates.build(workout_template_params)
    @workout_template.normalize_positions

    if structural_action?
      @workout_template.ensure_form_rows
      render_form_update
    elsif @workout_template.save
      redirect_to @workout_template, notice: "#{@workout_template.title} was created.", status: :see_other
    else
      @workout_template.ensure_form_rows
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @workout_template.ensure_form_rows
  end

  def update
    @workout_template.assign_attributes(workout_template_params)
    @workout_template.normalize_positions

    if structural_action?
      @workout_template.ensure_form_rows
      render_form_update
    elsif @workout_template.save
      redirect_to @workout_template, notice: "#{@workout_template.title} was updated.", status: :see_other
    else
      @workout_template.ensure_form_rows
      render :edit, status: :unprocessable_entity
    end
  end

  private
    def set_workout_template
      @workout_template = Current.household.workout_templates.find(params[:id])
    end

    def prepare_form
      @provenance_statuses = WorkoutTemplate.provenance_statuses.keys
      @block_kinds = WorkoutBlock::BLOCK_KINDS
      @dose_classes = WorkoutBlock::DOSE_CLASSES
      @entry_kinds = ExercisePrescription::ENTRY_KINDS
      @exercises = Current.household.exercises.order(:name)
      @exercise_options = @exercises.map { |exercise| [ exercise.name, exercise.id ] }
    end

    def workout_template_params
      params.fetch(:workout_template).permit(
        :title,
        :description,
        :provenance_status,
        :source_name,
        :source_url,
        workout_blocks_attributes: [
          :id,
          :title,
          :block_kind,
          :dose_class,
          :planned_duration_minutes,
          :notes,
          :_destroy,
          exercise_prescriptions_attributes: %i[
            id exercise_id entry_kind sets_count rep_min rep_max work_seconds rest_seconds
            target_rpe target_rir load_guidance dose_class notes _destroy
          ]
        ]
      )
    end

    def structural_action?
      if params[:add_block]
        @workout_template.add_block
      elsif params[:remove_block]
        @workout_template.remove_block(params[:remove_block])
      elsif params[:move_block]
        @workout_template.move_block(params[:move_block])
      elsif params[:add_prescription]
        @workout_template.add_prescription(params[:add_prescription])
      elsif params[:remove_prescription]
        @workout_template.remove_prescription(params[:remove_prescription])
      elsif params[:move_prescription]
        @workout_template.move_prescription(params[:move_prescription])
      end
    rescue ArgumentError => error
      @workout_template.errors.add(:base, error.message)
      true
    end

    def render_form_update
      render turbo_stream: turbo_stream.replace(
        "workout_template_form",
        partial: "workout_templates/form",
        locals: form_locals
      ), status: @workout_template.errors.any? ? :unprocessable_entity : :ok
    end

    def form_locals
      {
        workout_template: @workout_template,
        provenance_statuses: @provenance_statuses,
        block_kinds: @block_kinds,
        dose_classes: @dose_classes,
        entry_kinds: @entry_kinds,
        exercise_options: @exercise_options
      }
    end
end
