require "test_helper"

class TrainingSetTest < ActiveSupport::TestCase
  test "completed rows require the parent exercise primary measurement" do
    exercise = training_session_exercises(:draft_exercise)
    set = training_sets(:draft_set)

    set.completed = true
    assert_not set.valid?
    assert_includes set.errors[:base], "Record the required performance before completing this row."

    set.reps = 8
    assert_predicate set, :valid?

    exercise.update!(snapshot_performance_kind: :count, snapshot_target_count: 12, snapshot_target_count_unit: :steps)
    set.training_session_exercise = exercise
    set.assign_attributes(reps: nil, count: 12, count_unit: :steps)
    assert_predicate set, :valid?
  end

  test "interval completion requires work and recorded recovery" do
    exercise = training_session_exercises(:draft_exercise)
    exercise.update!(snapshot_performance_kind: :interval, snapshot_work_seconds: 20, snapshot_rest_seconds: 20)
    set = training_sets(:draft_set)
    set.assign_attributes(completed: true, duration_seconds: 20)

    assert_not set.valid?
    assert_includes set.errors[:rest_seconds], "is required for an interval"

    set.rest_seconds = 20
    assert_predicate set, :valid?
  end

  test "units and heart rate remain paired and ordered" do
    set = training_sets(:draft_set)
    set.assign_attributes(distance_amount: 1, average_heart_rate_bpm: 170, peak_heart_rate_bpm: 160)

    assert_not set.valid?
    assert_includes set.errors[:distance_unit], "must be provided with distance"
    assert_includes set.errors[:peak_heart_rate_bpm], "must be at least the average heart rate"
  end
end
