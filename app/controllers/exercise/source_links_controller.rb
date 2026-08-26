class Exercise::SourceLinksController < ApplicationController
  before_action :set_exercise

  def new
    unless @exercise.link_to_source_available?
      redirect_to @exercise, alert: "This exercise cannot be linked to the catalog right now.", status: :see_other
      return
    end

    @catalog_options = catalog_options
  end

  def create
    if WorkoutGuide::ImportRun.active?(Current.household)
      return render_active_run_conflict
    end
    unless @exercise.link_to_source_available?
      redirect_to @exercise, alert: "This exercise cannot be linked to the catalog right now.", status: :see_other
      return
    end

    record = catalog_import.record_for(source_key_param)
    result = @exercise.link_source_record!(record)
    return render_active_run_conflict if WorkoutGuide::ImportRun.active_refusal?(result)

    @catalog_result = catalog_result_hash(result)
    respond_with_catalog_result
  end

  private
    def set_exercise
      @exercise = Current.household.exercises.find(params[:exercise_id])
    end

    def catalog_import
      WorkoutGuide::Import.new(household: Current.household)
    end

    def catalog_options
      catalog_import.catalog_listing.map { |entry| [ entry[:name], entry[:source_key] ] }
    end

    def source_key_param
      params.require(:source_link).require(:source_key)
    end

    def catalog_result_hash(result)
      {
        "status" => result.status,
        "changes" => result.changes,
        "preserved" => result.preserved,
        "reasons" => result.reasons,
        "name" => result.exercise&.name
      }
    end

    def respond_with_catalog_result
      respond_to do |format|
        format.turbo_stream
        format.html do
          flash[:catalog_result] = @catalog_result
          redirect_to @exercise, status: :see_other
        end
      end
    end

    def render_active_run_conflict
      @source_panel_notice = "A Workout Guide import is already running. Link and Replace are unavailable until it finishes."
      @catalog_result = nil
      respond_to do |format|
        format.turbo_stream { render :conflict, status: :conflict }
        format.html { render "exercises/show", status: :conflict }
      end
    end
end
