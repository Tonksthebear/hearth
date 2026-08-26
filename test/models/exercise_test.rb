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

  test "add_muscle_target builds one blank row" do
    exercise = households(:home).exercises.build(name: "Targeted hinge", modality: :strength, movement_pattern: :hinge)

    assert_difference -> { exercise.exercise_muscle_targets.size }, 1 do
      exercise.add_muscle_target
    end
    assert_not exercise.exercise_muscle_targets.last.persisted?
    assert_nil exercise.exercise_muscle_targets.last.muscle_id
  end

  test "remove_muscle_target marks a persisted row and deletes an unsaved row" do
    exercise = exercises(:squat)
    exercise.exercise_muscle_targets.load
    persisted = exercise.exercise_muscle_targets.target.first
    unsaved = exercise.exercise_muscle_targets.build(muscle: muscles(:calves), role: :stabilizer)
    persisted_index = exercise.exercise_muscle_targets.target.index(persisted)
    unsaved_index = exercise.exercise_muscle_targets.target.index(unsaved)

    exercise.remove_muscle_target(unsaved_index)
    assert_not_includes exercise.exercise_muscle_targets.target, unsaved

    exercise.remove_muscle_target(persisted_index)
    assert persisted.marked_for_destruction?
  end

  test "remove_muscle_target raises for an out-of-range index" do
    exercise = exercises(:squat)

    error = assert_raises(ArgumentError) { exercise.remove_muscle_target(99) }
    assert_equal "Invalid exercise muscle target row.", error.message
  end

  test "two active targets naming one muscle are invalid and name the muscle" do
    exercise = households(:home).exercises.build(
      name: "Duplicate targets",
      modality: :strength,
      movement_pattern: :squat
    )
    exercise.exercise_muscle_targets.build(muscle: muscles(:quadriceps), role: :primary)
    exercise.exercise_muscle_targets.build(muscle: muscles(:quadriceps), role: :secondary)

    assert_not exercise.valid?
    assert_includes exercise.errors[:base], "Quadriceps is assigned more than once"
  end

  test "a new visual and visual item start at position 1" do
    exercise = households(:home).exercises.build(name: "Positioned hinge", modality: :strength, movement_pattern: :hinge)

    exercise.add_visual
    visual = exercise.exercise_visuals.last
    assert_equal 1, visual.position
    assert_equal 1, visual.exercise_visual_items.last.position

    visual.add_item
    assert_equal [ 1, 2 ], visual.exercise_visual_items.map(&:position)
  end
end
