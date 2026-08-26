require "test_helper"
require_relative "../test_helpers/exercise_visual_test_helper"
require_relative "../test_helpers/workout_guide_import_test_helper"

class ExerciseTest < ActiveSupport::TestCase
  include ExerciseVisualTestHelper
  include WorkoutGuideImportTestHelper
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

  test "link_source_record! preserves household scalars content and adds source children" do
    exercise = exercises(:squat)
    add_image_visual(exercise, alt_text: "Household photo")
    exercise.exercise_muscle_targets.create!(muscle: muscles(:calves), role: :stabilizer)
    exercise.save!
    household_visual_ids = exercise.exercise_visuals.map(&:id)
    household_positions = exercise.exercise_visuals.map(&:position)

    record = fixture_workout_guide_import.record_for("workout_guide:bench-press")
    result = exercise.link_source_record!(record)
    exercise.reload

    assert_equal "updated", result.status
    assert_equal "workout_guide:bench-press", exercise.source_key
    assert_equal "Goblet squat", exercise.name
    assert_equal "Keep the torso tall.", exercise.guidance
    assert_equal "Dumbbell", exercise.equipment
    assert_includes result.preserved, "name"
    assert_includes result.preserved, "guidance"
    assert_includes result.preserved, "visuals.household"
    assert_includes result.preserved, "targets.calves"
    assert_includes exercise.exercise_muscle_targets.map { |target| target.muscle.key }, "calves"
    assert_includes exercise.exercise_visuals.map(&:id), household_visual_ids.first
    assert_equal household_positions, exercise.exercise_visuals.select { |visual| household_visual_ids.include?(visual.id) }.map(&:position)
    assert exercise.exercise_visuals.any? { |visual| visual.source_key.present? }
  end

  test "link is refused when another household exercise already holds the source key" do
    fixture_workout_guide_import.run
    exercise = exercises(:squat)

    result = exercise.link_source_record!(fixture_workout_guide_import.record_for("workout_guide:bench-press"))
    assert_equal "failed", result.status
    assert_nil exercise.reload.source_key
  end

  test "link never matches by name without an explicit source key" do
    exercise = households(:home).exercises.create!(
      name: "Bench Press",
      modality: "strength",
      movement_pattern: "horizontal_push"
    )

    fixture_workout_guide_import.run
    assert_nil exercise.reload.source_key
  end

  test "replace_from_source! resets source owned fields and restores tombstoned visuals" do
    report = fixture_workout_guide_import.run
    exercise = report.results.find { |result| result.exercise&.source_key == "workout_guide:bench-press" }.exercise
    exercise.update!(equipment: "Household bar", name: "Household bench")
    exercise.exercise_muscle_targets.create!(muscle: muscles(:calves), role: :stabilizer)
    household_visual = add_image_visual(exercise, alt_text: "Household extra")
    exercise.save!
    source_visual = exercise.exercise_visuals.find { |visual| visual.source_key.present? }
    source_visual.destroy!

    record = fixture_workout_guide_import.record_for("workout_guide:bench-press")
    first = exercise.replace_from_source!(record)
    exercise.reload

    assert_equal "updated", first.status
    assert_equal "Bench Press", exercise.name
    assert_equal "Barbell", exercise.equipment
    assert_includes exercise.exercise_muscle_targets.map { |target| target.muscle.key }, "calves"
    assert exercise.exercise_visuals.exists?(id: household_visual.id)
    restored = exercise.exercise_visuals.find { |visual| visual.source_key.present? }
    assert_not_nil restored
    assert restored.sorted_items.all? { |item| item.file.attached? }
    assert_empty exercise.source_snapshot.fetch("removed_visual_keys")

    second = exercise.replace_from_source!(record)
    assert_equal "preserved", second.status
  end

  test "replace is unavailable while source_removed_at is present" do
    exercise = exercises(:squat)
    exercise.update!(source_key: "workout_guide:bench-press", source_removed_at: Time.current)

    assert_not exercise.replace_from_source_available?
    assert exercise.link_to_source_available? == false
  end

  test "catalog actions are unavailable while a run is active and return after failure" do
    exercise = exercises(:squat)
    run = WorkoutGuide::ImportRun.create!(household: households(:home), status: "queued")

    assert_not exercise.link_to_source_available?
    run.update!(status: "failed", finished_at: Time.current)
    assert exercise.reload.link_to_source_available?
  end

  private
    def current_target_pairs(exercise)
      exercise.exercise_muscle_targets.order(:id).map { |target| [ target.muscle.key, target.role ] }
    end
end
