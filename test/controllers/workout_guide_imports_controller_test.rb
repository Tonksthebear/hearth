require "test_helper"
require_relative "../test_helpers/workout_guide_import_test_helper"

class WorkoutGuideImportsControllerTest < ActionDispatch::IntegrationTest
  include WorkoutGuideImportTestHelper

  test "requires authentication" do
    post workout_guide_import_path
    assert_redirected_to new_session_path
  end

  test "enqueues the job and returns the running state without importing inline" do
    sign_in_as users(:one)

    assert_no_difference "Exercise.from_source.count" do
      assert_enqueued_with(job: WorkoutGuide::ImportJob) do
        post workout_guide_import_path, as: :turbo_stream
      end
    end

    assert_response :success
    run = WorkoutGuide::ImportRun.latest_for(households(:home))
    assert_equal "queued", run.status
    assert_match(/queued|running/i, response.body)
    assert_no_match(/Force reclaim|Reclaim this run|force-reclaim/i, response.body)
    assert_select "button", text: /reclaim/i, count: 0
  end

  test "a second post while a run is active enqueues no second job" do
    sign_in_as users(:one)
    WorkoutGuide::ImportRun.create!(household: households(:home), status: "running", started_at: Time.current)

    assert_no_enqueued_jobs only: WorkoutGuide::ImportJob do
      post workout_guide_import_path, as: :turbo_stream
    end

    assert_response :conflict
    assert_equal 1, WorkoutGuide::ImportRun.where(household: households(:home), status: "running").count
  end

  test "the index shows status labels after a completed run" do
    sign_in_as users(:one)
    WorkoutGuide::ImportRun.create!(
      household: households(:home),
      status: "completed",
      counts: WorkoutGuide::Import::STATUSES.index_with { |status| status == "created" ? 3 : 0 },
      skipped: [ { "name" => "Bench Press", "colliding_name" => "Bench Press" } ],
      failures: [],
      details: [ {
        "source_key" => "workout_guide:bench-press",
        "name" => "Bench Press",
        "status" => "created",
        "changes" => [ "created" ],
        "preserved" => [],
        "reasons" => []
      } ],
      started_at: Time.current,
      finished_at: Time.current
    )

    get exercises_path
    assert_response :success
    WorkoutGuide::Import::STATUSES.each { |status| assert_select "dt", text: status.humanize }
    assert_select "p", text: /Bench Press/
    assert_select "p", text: /Collides with household exercise Bench Press/
  end
end
