require "test_helper"

class ExercisePrescriptionTest < ActiveSupport::TestCase
  test "accepts every catalog primary performance kind" do
    base = {
      exercise: exercises(:squat),
      position: 2,
      sets_count: 1
    }
    prescriptions = [
      workout_blocks(:strength).exercise_prescriptions.build(**base, performance_kind: :reps, rep_min: 8, rep_max: 10),
      workout_blocks(:strength).exercise_prescriptions.build(**base, performance_kind: :duration, work_seconds: 45),
      workout_blocks(:strength).exercise_prescriptions.build(**base, performance_kind: :distance, target_distance_amount: 400, target_distance_unit: :m),
      workout_blocks(:strength).exercise_prescriptions.build(**base, performance_kind: :count, target_count: 12, target_count_unit: :flights),
      workout_blocks(:strength).exercise_prescriptions.build(**base, performance_kind: :interval, work_seconds: 20, rest_seconds: 20)
    ]

    prescriptions.each { |prescription| assert_predicate prescription, :valid?, prescription.errors.full_messages.to_sentence }
  end

  test "requires the selected primary target and matching units" do
    prescription = workout_blocks(:strength).exercise_prescriptions.build(
      exercise: exercises(:squat),
      position: 2,
      sets_count: 1,
      performance_kind: :distance,
      target_distance_amount: 400
    )

    assert_not prescription.valid?
    assert_includes prescription.errors[:target_distance_unit], "must be provided with target distance"
  end

  test "rejects inverted rep and heart-rate ranges and incomplete intervals" do
    prescription = exercise_prescriptions(:squat_sets)
    prescription.assign_attributes(
      rep_min: 10,
      rep_max: 8,
      performance_kind: :interval,
      work_seconds: nil,
      rest_seconds: nil,
      target_heart_rate_min: 170,
      target_heart_rate_max: 150,
      target_heart_rate_unit: :bpm
    )

    assert_not prescription.valid?
    assert_includes prescription.errors[:rep_max], "must be at least the minimum reps"
    assert_includes prescription.errors[:work_seconds], "is required for intervals"
    assert_includes prescription.errors[:rest_seconds], "is required for intervals"
    assert_includes prescription.errors[:target_heart_rate_max], "must be at least the minimum heart rate"
  end
end
