class TrainingSessionsController < ApplicationController
  before_action :set_training_session, only: %i[ show edit update destroy ]
  before_action :prepare_form, only: %i[ new create edit update ]

  def new
    @training_session = TrainingSession.build_ad_hoc(person: Current.person, performed_on: selected_date)
  end

  def create
    if params[:planned_workout_id].present?
      planned_workout = Current.person.planned_workouts.find(params[:planned_workout_id])
      begin
        session = planned_workout.start!
      rescue ActiveRecord::RecordInvalid
        redirect_to planned_workout_return_path(planned_workout),
          alert: planned_workout.errors.full_messages.to_sentence,
          status: :see_other
        return
      end
      redirect_to edit_training_session_path(session), notice: "Workout started.", status: :see_other
      return
    elsif params[:template_id].present?
      template = Current.household.workout_templates.find(params[:template_id])
      session = TrainingSession.start_from(template: template, person: Current.person)
      redirect_to edit_training_session_path(session), notice: "Workout started.", status: :see_other
      return
    end

    @training_session = Current.person.training_sessions.build(training_session_params)
    @training_session.household = Current.household
    @training_session.started_at ||= Time.current
    @training_session.normalize_positions

    if structural_action?
      @training_session.ensure_form_rows
      render_form_update
    elsif @training_session.save
      redirect_to edit_training_session_path(@training_session), notice: "Workout in progress saved.", status: :see_other
    else
      @training_session.ensure_form_rows
      render :new, status: :unprocessable_entity
    end
  end

  def show
  end

  def edit
    redirect_to @training_session if @training_session.completed?
  end

  def update
    if @training_session.completed?
      redirect_to @training_session, alert: "Completed workouts are read-only.", status: :see_other
      return
    end

    @training_session.assign_attributes(training_session_params)
    @training_session.normalize_positions

    if structural_action?
      @training_session.ensure_form_rows
      render_form_update
    elsif params[:complete]
      complete_training_session
    elsif @training_session.save
      redirect_to edit_training_session_path(@training_session), notice: "Workout in progress saved.", status: :see_other
    else
      @training_session.ensure_form_rows
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @training_session.completed?
      redirect_to @training_session, alert: "Completed workouts cannot be deleted.", status: :see_other
    else
      @training_session.destroy!
      redirect_to training_week_path(date: @training_session.performed_on), notice: "Workout in progress deleted.", status: :see_other
    end
  end

  private
    def set_training_session
      @training_session = Current.person.training_sessions.find(params[:id])
    end

    def planned_workout_return_path(planned_workout)
      params[:return_to] == "today" ? root_path : activity_week_path(date: params[:date].presence || planned_workout.scheduled_on)
    end

    def selected_date
      Date.iso8601(params[:date].to_s)
    rescue ArgumentError, Date::Error
      Date.current
    end

    def prepare_form
      @exercises = Current.household.exercises.order(:name)
      @exercise_options = [ [ "Structured inline exercise", "" ] ] +
        @exercises.map { |exercise| [ exercise.name, exercise.id ] }
      @modalities = Exercise::MODALITIES
      @movement_patterns = Exercise::MOVEMENT_PATTERNS
      @block_kinds = WorkoutBlock::BLOCK_KINDS
      @dose_classes = WorkoutBlock::DOSE_CLASSES
      @performance_kind_options = ExercisePrescription::PERFORMANCE_KINDS.map { |value| [ value.humanize, value ] }
      @distance_unit_options = TrainingSet::DISTANCE_UNITS.map { |value| [ value, value ] }
      @count_unit_options = TrainingSet::COUNT_UNITS.map { |value| [ value.humanize, value ] }
      @heart_rate_unit_options = ExercisePrescription::HEART_RATE_UNITS.map { |value| [ value.humanize, value ] }
      @load_unit_options = TrainingSet::LOAD_UNITS.map { |value| [ value, value ] }
      @difficulty_options = TrainingSessionExercise::DIFFICULTIES.map { |value| [ value.humanize, value ] }
    end

    def training_session_params
      params.fetch(:training_session).permit(
        :snapshot_title,
        :performed_on,
        :notes,
        training_session_blocks_attributes: [
          :id,
          :snapshot_title,
          :snapshot_block_kind,
          :snapshot_dose_class,
          :actual_duration_seconds,
          :notes,
          :_destroy,
          training_session_exercises_attributes: [
            :id,
            :exercise_id,
            :snapshot_name,
            :snapshot_modality,
            :snapshot_movement_pattern,
            :snapshot_equipment,
            :snapshot_guidance,
            :snapshot_performance_kind,
            :snapshot_dose_class,
            :snapshot_sets_count,
            :snapshot_rep_min,
            :snapshot_rep_max,
            :snapshot_work_seconds,
            :snapshot_rest_seconds,
            :snapshot_target_distance_amount,
            :snapshot_target_distance_unit,
            :snapshot_target_count,
            :snapshot_target_count_unit,
            :snapshot_per_side,
            :snapshot_tempo_cue,
            :snapshot_target_heart_rate_min,
            :snapshot_target_heart_rate_max,
            :snapshot_target_heart_rate_unit,
            :snapshot_target_rpe,
            :snapshot_target_rir,
            :snapshot_load_guidance,
            :difficulty,
            :soreness_or_pain,
            :substitution,
            :next_time_adjustment,
            :notes,
            :_destroy,
            training_sets_attributes: %i[
              id dose_class reps load_amount load_unit duration_seconds rest_seconds
              distance_amount distance_unit count count_unit average_heart_rate_bpm peak_heart_rate_bpm
              rpe rir completed notes _destroy
            ]
          ]
        ]
      )
    end

    def structural_action?
      if params[:add_session_block]
        @training_session.add_block
      elsif params[:remove_session_block]
        @training_session.remove_block(params[:remove_session_block])
      elsif params[:add_session_exercise]
        @training_session.add_exercise(params[:add_session_exercise])
      elsif params[:remove_session_exercise]
        @training_session.remove_exercise(params[:remove_session_exercise])
      elsif params[:add_training_set]
        @training_session.add_set(params[:add_training_set])
      elsif params[:remove_training_set]
        @training_session.remove_set(params[:remove_training_set])
      end
    rescue ArgumentError => error
      @training_session.errors.add(:base, error.message)
      true
    end

    def complete_training_session
      @training_session.save!
      @training_session.complete!
      redirect_to @training_session, notice: "Workout completed.", status: :see_other
    rescue ActiveRecord::RecordInvalid
      @training_session.ensure_form_rows
      render :edit, status: :unprocessable_entity
    end

    def render_form_update
      render turbo_stream: turbo_stream.replace(
        "training_session_form",
        partial: "training_sessions/form",
        locals: form_locals
      ), status: @training_session.errors.any? ? :unprocessable_entity : :ok
    end

    def form_locals
      {
        training_session: @training_session,
        exercise_options: @exercise_options,
        modalities: @modalities,
        movement_patterns: @movement_patterns,
        block_kinds: @block_kinds,
        dose_classes: @dose_classes,
        performance_kind_options: @performance_kind_options,
        distance_unit_options: @distance_unit_options,
        count_unit_options: @count_unit_options,
        heart_rate_unit_options: @heart_rate_unit_options,
        load_unit_options: @load_unit_options,
        difficulty_options: @difficulty_options
      }
    end
end
