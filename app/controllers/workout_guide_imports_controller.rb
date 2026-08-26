class WorkoutGuideImportsController < ApplicationController
  def create
    result = WorkoutGuide::ImportRun.start!(household: Current.household)
    @import_run = result.run
    @import_action_label = WorkoutGuide::ImportRun.action_label(Current.household)
    @catalog_import_available = !WorkoutGuide::ImportRun.active?(Current.household)

    respond_to do |format|
      format.turbo_stream { render :create, status: result.refused? ? :conflict : :ok }
      format.html { redirect_to exercises_path, status: :see_other }
    end
  end
end
