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
end
