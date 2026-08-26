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

  test "replace_muscle_targets! creates the given set on a persisted exercise" do
    exercise = households(:home).exercises.create!(
      name: "Targeted carry",
      modality: :strength,
      movement_pattern: :carry
    )

    exercise.replace_muscle_targets!([
      { muscle_key: "forearms", role: "primary" },
      { muscle_key: "glutes", role: "secondary" }
    ])

    assert_equal(
      [ [ "forearms", "primary" ], [ "glutes", "secondary" ] ],
      exercise.ordered_muscle_targets.map { |target| [ target.muscle.key, target.role ] }
    )
  end

  test "replace_muscle_targets! replaces the full set in one call" do
    exercise = exercises(:squat)
    exercise.replace_muscle_targets!([
      { "muscle_key" => "quadriceps", "role" => "secondary" },
      { "muscle_key" => "calves", "role" => "stabilizer" }
    ])

    assert_equal(
      [ [ "quadriceps", "secondary" ], [ "calves", "stabilizer" ] ],
      exercise.ordered_muscle_targets.map { |target| [ target.muscle.key, target.role ] }
    )
    refute exercise.muscles.exists?(key: "glutes")
  end

  test "an empty replacement clears every target" do
    exercise = exercises(:squat)

    exercise.replace_muscle_targets!([])

    assert_empty exercise.exercise_muscle_targets.reload
  end

  test "duplicate muscle keys raise ArgumentError and write nothing" do
    exercise = exercises(:squat)
    prior = current_target_pairs(exercise)

    [
      [ { muscle_key: "glutes", role: "primary" }, { muscle_key: "glutes", role: "primary" } ],
      [ { muscle_key: "glutes", role: "primary" }, { muscle_key: "glutes", role: "secondary" } ]
    ].each do |entries|
      error = assert_raises(ArgumentError) { exercise.replace_muscle_targets!(entries) }
      assert_match(/unique/i, error.message)
      assert_equal prior, current_target_pairs(exercise.reload)
    end
  end

  test "unknown keys and invalid roles raise ArgumentError and write nothing" do
    exercise = exercises(:squat)
    prior = current_target_pairs(exercise)

    unknown = assert_raises(ArgumentError) {
      exercise.replace_muscle_targets!([ { muscle_key: "not_a_muscle", role: "primary" } ])
    }
    invalid = assert_raises(ArgumentError) {
      exercise.replace_muscle_targets!([ { muscle_key: "glutes", role: "assistant" } ])
    }

    assert_match(/Unknown muscle key/, unknown.message)
    assert_match(/Invalid muscle target role/, invalid.message)
    assert_equal prior, current_target_pairs(exercise.reload)
  end

  test "a mid-replacement write failure leaves the prior target set intact" do
    exercise = exercises(:squat)
    prior = current_target_pairs(exercise)
    original = ExerciseMuscleTarget.instance_method(:save!)
    ExerciseMuscleTarget.define_method(:save!) do |*arguments, **keywords, &block|
      raise ActiveRecord::RecordInvalid, self if muscle.key == "calves"

      original.bind_call(self, *arguments, **keywords, &block)
    end

    assert_raises(ActiveRecord::RecordInvalid) do
      exercise.replace_muscle_targets!([
        { muscle_key: "glutes", role: "primary" },
        { muscle_key: "calves", role: "stabilizer" }
      ])
    end
    assert_equal prior, current_target_pairs(exercise.reload)
  ensure
    ExerciseMuscleTarget.define_method(:save!) do |*arguments, **keywords, &block|
      original.bind_call(self, *arguments, **keywords, &block)
    end
  end

  test "ordered_muscle_targets follows display position after replacement and when preloaded" do
    exercise = exercises(:bike)
    exercise.replace_muscle_targets!([
      { muscle_key: "calves", role: "stabilizer" },
      { muscle_key: "glutes", role: "secondary" },
      { muscle_key: "quadriceps", role: "primary" }
    ])

    assert_equal %w[glutes quadriceps calves], exercise.ordered_muscle_targets.map { |target| target.muscle.key }

    preloaded = Exercise.includes(exercise_muscle_targets: :muscle).find(exercise.id)
    keys = nil
    assert_queries_count(0) do
      keys = preloaded.ordered_muscle_targets.map { |target| target.muscle.key }
    end
    assert_equal %w[glutes quadriceps calves], keys
  end

  private
    def current_target_pairs(exercise)
      exercise.exercise_muscle_targets.order(:id).map { |target| [ target.muscle.key, target.role ] }
    end
end
