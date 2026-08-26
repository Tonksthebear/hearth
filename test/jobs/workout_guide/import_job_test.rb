require "test_helper"
require_relative "../../test_helpers/workout_guide_import_test_helper"

class WorkoutGuide::ImportJobTest < ActiveJob::TestCase
  include WorkoutGuideImportTestHelper

  test "the job body delegates to perform! and holds no import logic" do
    source = File.read(Rails.root.join("app/jobs/workout_guide/import_job.rb"))
    assert_match(/ImportRun\.find\(import_run_id\)\.perform!/, source)
    assert_no_match(/WorkoutGuide::Import\.new/, source)
    assert_no_match(/merge_source_record!/, source)
  end

  test "perform runs the persisted run" do
    run = WorkoutGuide::ImportRun.create!(household: households(:home), status: "queued")

    with_fixture_workout_guide_import do
      WorkoutGuide::ImportJob.perform_now(run.id)
    end

    assert_equal "completed", run.reload.status
    assert_equal 3, run.counts.fetch("created")
  end
end
