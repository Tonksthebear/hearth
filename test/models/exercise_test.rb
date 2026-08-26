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

  test "source predicates and from_source follow source_key and source_removed_at" do
    household = households(:home)
    linked = household.exercises.create!(
      name: "Linked hinge",
      modality: :strength,
      movement_pattern: :hinge,
      source_key: "linked-hinge"
    )
    removed = household.exercises.create!(
      name: "Removed hinge",
      modality: :strength,
      movement_pattern: :hinge,
      source_key: "removed-hinge",
      source_removed_at: Time.current
    )

    assert linked.source_linked?
    assert linked.merges_automatically?
    assert_not linked.source_removed?
    assert removed.source_removed?
    assert_not removed.merges_automatically?
    assert_includes Exercise.from_source, linked
    assert_includes Exercise.from_source, removed
    refute_includes Exercise.from_source, exercises(:squat)

    removed.source_key = nil
    assert_not removed.valid?
    assert_includes removed.errors[:source_removed_at], "requires a source key"
  end
end
