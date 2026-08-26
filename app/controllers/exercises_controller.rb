class ExercisesController < ApplicationController
  before_action :set_exercise, only: %i[ show edit update ]
  before_action :prepare_form, only: %i[ new create edit update ]

  def index
    @exercises = Current.household.exercises.order(:name)
    @import_run = WorkoutGuide::ImportRun.latest_for(Current.household)
    @import_action_label = WorkoutGuide::ImportRun.action_label(Current.household)
    @catalog_import_available = !WorkoutGuide::ImportRun.active?(Current.household)
    @catalog_credits = Current.household.exercises
      .from_source_namespace(WorkoutGuide::Import::SOURCE_NAMESPACE)
      .catalog_credits
  end

  def show
    @catalog_result = flash[:catalog_result]
    @source_panel_notice = flash[:source_panel_notice]
    @muscle_map = MuscleMap.new(@exercise)
  end

  def new
    @exercise = Current.household.exercises.build
  end

  def create
    @exercise = Current.household.exercises.build(exercise_attributes)
    @exercise.normalize_positions

    if structural_action?
      @exercise.preserve_visuals_for_form
      render_form_update
    elsif @exercise.save
      redirect_to @exercise, notice: "#{@exercise.name} was created.", status: :see_other
    else
      @exercise.preserve_visuals_for_form
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    @exercise.assign_attributes(exercise_attributes)
    @exercise.normalize_positions

    if structural_action?
      @exercise.preserve_visuals_for_form
      render_form_update
    elsif @exercise.save
      redirect_to @exercise, notice: "#{@exercise.name} was updated.", status: :see_other
    else
      @exercise.preserve_visuals_for_form
      render :edit, status: :unprocessable_entity
    end
  end

  private
    def set_exercise
      scope = Current.household.exercises
      if action_name == "show"
        scope = scope.includes(
          exercise_visuals: { exercise_visual_items: { file_attachment: :blob } },
          exercise_muscle_targets: :muscle
        )
      end
      @exercise = scope.find(params[:id])
    end

    def prepare_form
      @modalities = Exercise::MODALITIES
      @movement_patterns = Exercise::MOVEMENT_PATTERNS
      @muscles = Muscle.displayed
      @target_roles = ExerciseMuscleTarget::ROLES
      @visual_kinds = ExerciseVisual::KINDS
      @provenance_statuses = ExerciseVisual.provenance_statuses.keys
    end

    def exercise_params
      params.fetch(:exercise).permit(
        :name,
        :modality,
        :movement_pattern,
        :equipment,
        :guidance,
        exercise_muscle_targets_attributes: [
          :id,
          :muscle_id,
          :role,
          :_destroy
        ],
        exercise_visuals_attributes: [
          :id,
          :kind,
          :position,
          :frame_interval_ms,
          :alt_text,
          :caption,
          :display_attribution,
          :provenance_status,
          :source_key,
          :_destroy,
          exercise_visual_items_attributes: [
            :id,
            :position,
            :source_identifier,
            :source_checksum,
            :file,
            :_destroy,
            { source_metadata: {} }
          ]
        ]
      )
    end

    def exercise_attributes
      exercise_params.tap do |attributes|
        Array(attributes[:exercise_visuals_attributes]&.values).each do |visual|
          Array(visual[:exercise_visual_items_attributes]&.values).each do |item|
            file = item[:file]
            next unless file.is_a?(String) && file.present?
            next if ActiveStorage::Blob.find_signed(file)

            item.delete(:file)
            item[:file_reference_invalid] = true
          end
        end
      end
    end

    def structural_action?
      if params[:add_muscle_target]
        @exercise.add_muscle_target
      elsif params[:remove_muscle_target]
        @exercise.remove_muscle_target(params[:remove_muscle_target])
      elsif params[:add_visual]
        @exercise.add_visual
      elsif params[:remove_visual]
        @exercise.remove_visual(params[:remove_visual])
      elsif params[:add_visual_item]
        @exercise.add_visual_item(params[:add_visual_item])
      elsif params[:remove_visual_item]
        @exercise.remove_visual_item(params[:remove_visual_item])
      end
    rescue ArgumentError => error
      @exercise.errors.add(:base, error.message)
      true
    end

    def render_form_update
      status = @exercise.errors.any? ? :unprocessable_entity : :ok
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace("exercise_form", partial: "exercises/form", locals: form_locals), status: status
        end
        format.html { render(@exercise.persisted? ? :edit : :new, status: status) }
      end
    end

    def form_locals
      {
        exercise: @exercise,
        modalities: @modalities,
        movement_patterns: @movement_patterns,
        muscles: @muscles,
        target_roles: @target_roles,
        visual_kinds: @visual_kinds,
        provenance_statuses: @provenance_statuses
      }
    end
end
