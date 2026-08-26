class WorkoutGuide::ImportJob < ApplicationJob
  def perform(import_run_id)
    WorkoutGuide::ImportRun.find(import_run_id).perform!
  end
end
