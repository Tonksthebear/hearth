require "test_helper"

class ExerciseTest < ActiveSupport::TestCase
  test "requires catalog taxonomy and exposes exact enums" do
    exercise = households(:home).exercises.build

    assert_not exercise.valid?
    assert_includes exercise.errors[:name], "can't be blank"
    assert_equal Exercise::MODALITIES, Exercise.modalities.keys
    assert_equal Exercise::MOVEMENT_PATTERNS, Exercise.movement_patterns.keys
  end

  test "name is unique within the household" do
    duplicate = households(:home).exercises.build(
      name: exercises(:squat).name,
      modality: :strength,
      movement_pattern: :squat
    )

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:name], "has already been taken"
  end

  test "household created exercises use the same muscle targets as imported exercises" do
    exercise = households(:home).exercises.create!(
      name: "Household squat",
      modality: :strength,
      movement_pattern: :squat
    )
    target = exercise.exercise_muscle_targets.create!(muscle: muscles(:quadriceps), role: :primary)

    assert_equal muscles(:quadriceps), target.muscle
    assert_equal "primary", target.role
    assert_includes exercise.muscles, muscles(:quadriceps)
    refute_includes ExerciseMuscleTarget.column_names, "household_id"
  end
end
