class Exercise::SourceReplacementsController < ApplicationController
  before_action :set_exercise

  def create
    if WorkoutGuide::ImportRun.active?(Current.household)
      return render_active_run_conflict
    end
    unless @exercise.replace_from_source_available?
      redirect_to @exercise, alert: "This exercise cannot be replaced from the catalog right now.", status: :see_other
      return
    end

    record = WorkoutGuide::Import.new(household: Current.household).record_for(@exercise.source_key)
    result = @exercise.replace_from_source!(record)
    return render_active_run_conflict if WorkoutGuide::ImportRun.active_refusal?(result)

    @muscle_map = MuscleMap.new(@exercise.reload)
    @catalog_result = {
      "status" => result.status,
      "changes" => result.changes,
      "preserved" => result.preserved,
      "reasons" => result.reasons,
      "name" => result.exercise&.name
    }
    respond_to do |format|
      format.turbo_stream
      format.html do
        flash[:catalog_result] = @catalog_result
        redirect_to @exercise, status: :see_other
      end
    end
  end

  private
    def set_exercise
      @exercise = Current.household.exercises.find(params[:exercise_id])
    end

    def render_active_run_conflict
      @source_panel_notice = "A Workout Guide import is already running. Link and Replace are unavailable until it finishes."
      @catalog_result = nil
      @muscle_map = MuscleMap.new(@exercise)
      respond_to do |format|
        format.turbo_stream { render :conflict, status: :conflict }
        format.html { render "exercises/show", status: :conflict }
      end
    end
end
