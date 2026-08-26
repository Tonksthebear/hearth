require "test_helper"

class MuscleMapTest < ActiveSupport::TestCase
  test "resolves roles and orders text targets by persisted display position" do
    exercise = households(:home).exercises.create!(
      name: "Mapped hinge",
      modality: "strength",
      movement_pattern: "hinge"
    )
    exercise.exercise_muscle_targets.create!(muscle: muscles(:hamstrings), role: :primary)
    exercise.exercise_muscle_targets.create!(muscle: muscles(:glutes), role: :secondary)
    exercise.exercise_muscle_targets.create!(muscle: muscles(:chest), role: :stabilizer)

    muscle_map = MuscleMap.new(exercise)
    assert_equal "primary", muscle_map.role_for("hamstrings")
    assert_equal "secondary", muscle_map.role_for("glutes")
    assert_equal "stabilizer", muscle_map.role_for("chest")
    assert_nil muscle_map.role_for("biceps")
    assert_equal(
      exercise.ordered_muscle_targets.map { |target| target.muscle.key },
      muscle_map.text_targets.map { |target| target.muscle.key }
    )
  end

  test "allowlist is empty and frozen" do
    assert_equal [], MuscleMap::UNMAPPED_KEYS
    assert_predicate MuscleMap::UNMAPPED_KEYS, :frozen?
  end
end
