require "test_helper"
require_relative "../../test_helpers/workout_guide_import_test_helper"

class WorkoutGuide::ImportRunTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include WorkoutGuideImportTestHelper

  test "start! creates one queued row and enqueues the job" do
    household = households(:home)

    assert_difference "WorkoutGuide::ImportRun.count", 1 do
      assert_enqueued_with(job: WorkoutGuide::ImportJob) do
        result = WorkoutGuide::ImportRun.start!(household:)
        assert_not result.refused?
        assert_equal "queued", result.run.status
        assert_nil result.run.started_at
      end
    end
  end

  test "a second start! while a run is queued creates no second row" do
    household = households(:home)
    first = WorkoutGuide::ImportRun.start!(household:)
    assert_not first.refused?

    assert_no_difference "WorkoutGuide::ImportRun.count" do
      assert_no_enqueued_jobs only: WorkoutGuide::ImportJob do
        second = WorkoutGuide::ImportRun.start!(household:)
        assert second.refused?
        assert_equal first.run.id, second.run.id
      end
    end
  end

  test "the active household index refuses a second queued insert" do
    household = households(:home)
    WorkoutGuide::ImportRun.create!(household:, status: "queued")

    assert_raises(ActiveRecord::RecordNotUnique) do
      WorkoutGuide::ImportRun.insert_all!([ {
        household_id: household.id,
        status: "queued",
        counts: {},
        skipped: [],
        failures: [],
        details: [],
        created_at: Time.current,
        updated_at: Time.current
      } ])
    end
  end

  test "a queued run stays active after a long delay" do
    household = households(:home)
    run = WorkoutGuide::ImportRun.create!(household:, status: "queued", created_at: 30.days.ago)

    travel_to 30.days.from_now do
      assert run.reload.active?
      assert WorkoutGuide::ImportRun.active?(household)
      result = WorkoutGuide::ImportRun.start!(household:)
      assert result.refused?
      assert_equal "queued", run.reload.status
    end
  end

  test "a running run stays active after a long delay" do
    household = households(:home)
    run = WorkoutGuide::ImportRun.create!(
      household:,
      status: "running",
      started_at: 30.days.ago,
      created_at: 30.days.ago
    )

    travel_to 30.days.from_now do
      assert run.reload.active?
      result = WorkoutGuide::ImportRun.start!(household:)
      assert result.refused?
      assert_equal "running", run.reload.status
    end
  end

  test "failed and completed runs never block a new start" do
    household = households(:home)
    WorkoutGuide::ImportRun.create!(household:, status: "failed", finished_at: Time.current)
    result = WorkoutGuide::ImportRun.start!(household:)
    assert_not result.refused?

    result.run.update!(status: "completed", finished_at: Time.current)
    follow_on = WorkoutGuide::ImportRun.start!(household:)
    assert_not follow_on.refused?
    assert_not_equal result.run.id, follow_on.run.id
  end

  test "perform! stores counts skipped details and completed" do
    household = households(:home)
    run = WorkoutGuide::ImportRun.create!(household:, status: "queued")

    with_fixture_workout_guide_import do
      run.perform!
    end

    run.reload
    assert_equal "completed", run.status
    assert run.started_at.present?
    assert run.finished_at.present?
    assert_equal 3, run.counts.fetch("created")
    assert_equal [], run.failures
    assert run.details.any? { |entry| entry["status"] == "created" }
  end

  test "perform! marks failed with a safe message and does not raise" do
    household = households(:home)
    run = WorkoutGuide::ImportRun.create!(household:, status: "queued")
    failing = Object.new
    failing.define_singleton_method(:run) { raise "secret path /tmp/catalog" }

    with_stubbed_method(WorkoutGuide::Import, :new, ->(**) { failing }) do
      run.perform!
    end

    run.reload
    assert_equal "failed", run.status
    assert_equal [ { "message" => WorkoutGuide::ImportRun::SAFE_FAILURE_MESSAGE } ], run.failures
    assert_no_match(/secret path/, run.failures.to_s)
  end

  test "enqueue failure marks the run failed and frees the household" do
    household = households(:home)

    with_stubbed_method(WorkoutGuide::ImportJob, :perform_later, ->(*) { raise "queue down" }) do
      result = WorkoutGuide::ImportRun.start!(household:)
      assert result.refused?
      assert_equal "failed", result.run.status
      assert_equal [ { "message" => WorkoutGuide::ImportRun::SAFE_ENQUEUE_FAILURE_MESSAGE } ], result.run.failures
    end

    follow_on = WorkoutGuide::ImportRun.start!(household:)
    assert_not follow_on.refused?
  end

  test "elapsed time never writes a terminal status" do
    household = households(:home)
    run = WorkoutGuide::ImportRun.create!(household:, status: "queued", created_at: 30.days.ago)

    travel_to 30.days.from_now do
      assert_equal "queued", run.reload.status
      assert_not WorkoutGuide::ImportRun.const_defined?(:STALE_AFTER)
      assert_not WorkoutGuide::ImportRun.instance_methods(false).include?(:reclaim!)
    end
  end

  test "queue age is derived from created_at and does not change availability" do
    household = households(:home)
    run = WorkoutGuide::ImportRun.create!(household:, status: "running", started_at: Time.current, created_at: 2.hours.ago)

    assert run.queue_age >= 2.hours
    assert WorkoutGuide::ImportRun.active?(household)
    assert_not exercises(:squat).link_to_source_available?
    assert_not exercises(:squat).replace_from_source_available?
  end

  test "a second household insert still violates the installation check" do
    assert_raises(ActiveRecord::CheckViolation) do
      Household.insert_all([ {
        name: "Other",
        installation_key: 2,
        created_at: Time.current,
        updated_at: Time.current
      } ])
    end
  end

  test "household exercises are scoped by household_id" do
    household = households(:home)
    assert_match %r{"exercises"\."household_id" = #{household.id}}, household.exercises.to_sql
  end
end
