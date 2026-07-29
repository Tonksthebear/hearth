require "test_helper"

class ExercisePrescriptionTest < ActiveSupport::TestCase
  test "requires a rep range or timed work" do
    prescription = workout_blocks(:strength).exercise_prescriptions.build(
      exercise: exercises(:squat),
      position: 2,
      sets_count: 1,
      entry_kind: :set
    )

    assert_not prescription.valid?
    assert_includes prescription.errors[:base], "Specify a rep range or timed work."
  end

  test "rejects inverted rep ranges and invalid interval shapes" do
    prescription = exercise_prescriptions(:squat_sets)
    prescription.rep_min = 10
    prescription.rep_max = 8
    prescription.entry_kind = :interval
    prescription.work_seconds = nil

    assert_not prescription.valid?
    assert_includes prescription.errors[:rep_max], "must be at least the minimum reps"
    assert_includes prescription.errors[:base], "Intervals require timed work."
  end
end
