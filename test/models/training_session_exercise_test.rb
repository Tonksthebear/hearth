require "test_helper"

class TrainingSessionExerciseTest < ActiveSupport::TestCase
  test "timestamps completion only while every active row is complete" do
    exercise = training_session_exercises(:draft_exercise)
    set = training_sets(:draft_set)

    set.update!(completed: true, reps: 8)
    assert_not_nil exercise.reload.completed_at

    set.update!(completed: false)
    assert_nil exercise.reload.completed_at
  end

  test "completed session feedback does not change its exercise completion timestamp" do
    exercise = training_session_exercises(:sunday_squat)
    original = Time.zone.parse("2026-07-26 10:00")
    exercise.update_column(:completed_at, original)

    training_sets(:sunday_squat_one).update!(notes: "Felt steady")

    assert_equal original, exercise.reload.completed_at
  end

  test "allows no primary target while validating paired units and heart-rate order" do
    exercise = training_session_exercises(:draft_exercise)
    exercise.assign_attributes(
      snapshot_performance_kind: :distance,
      snapshot_rep_min: nil,
      snapshot_rep_max: nil,
      snapshot_target_distance_amount: nil,
      snapshot_target_distance_unit: :km,
      snapshot_target_count_unit: :laps,
      snapshot_target_heart_rate_min: 180,
      snapshot_target_heart_rate_max: 100,
      snapshot_target_heart_rate_unit: :bpm
    )

    assert_not exercise.valid?
    assert_not_includes exercise.errors[:snapshot_target_distance_amount], "is required for distance work"
    assert_includes exercise.errors[:snapshot_target_distance_unit], "must be provided with target distance"
    assert_includes exercise.errors[:snapshot_target_count_unit], "must be provided with target count"
    assert_includes exercise.errors[:snapshot_target_heart_rate_max], "must be at least the minimum heart rate"
  end

  test "edits feedback on a migrated ad hoc exercise without prescription targets" do
    exercise = training_session_exercises(:draft_exercise)
    exercise.update_columns(
      snapshot_rep_min: nil,
      snapshot_rep_max: nil,
      snapshot_work_seconds: nil,
      snapshot_target_distance_amount: nil,
      snapshot_target_distance_unit: nil,
      snapshot_target_count: nil,
      snapshot_target_count_unit: nil
    )

    assert exercise.update(difficulty: :about_right, next_time_adjustment: "Repeat it")
    assert_predicate exercise, :about_right?
  end

  test "summarizes an untargeted ad hoc exercise with only its row count" do
    exercise = training_session_exercises(:draft_exercise)
    exercise.assign_attributes(snapshot_sets_count: 1, snapshot_rep_min: nil, snapshot_rep_max: nil)

    assert_equal "1 row", exercise.target_summary
  end

  test "prefills secondary work duration for distance and count rows" do
    exercise = training_session_exercises(:draft_exercise)

    %w[distance count].each do |kind|
      exercise.snapshot_performance_kind = kind
      exercise.snapshot_work_seconds = 600
      exercise.training_sets.clear
      exercise.add_set

      assert_equal 600, exercise.active_sets.first.duration_seconds
    end
  end

  test "pluralizes a single performed row" do
    exercise = training_session_exercises(:draft_exercise)
    exercise.snapshot_sets_count = 1

    assert_match(/\A1 row ·/, exercise.target_summary)
  end
end
