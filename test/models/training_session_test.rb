require "test_helper"

class TrainingSessionTest < ActiveSupport::TestCase
  test "uses household-friendly source copy for a personal snapshot" do
    session = TrainingSession.new(snapshot_source_name: nil)

    assert_equal "From your household", session.snapshot_source_label
  end

  test "starts a persisted in-progress workout with immutable template and exercise snapshots" do
    session = TrainingSession.start_from(
      template: workout_templates(:balanced),
      person: people(:one),
      performed_on: Date.new(2026, 7, 31)
    )

    assert_predicate session, :persisted?
    assert_not_predicate session, :completed?
    assert_equal [ 1, 2 ], session.training_session_blocks.map(&:position)
    assert_equal 1200, session.training_session_blocks.first.actual_duration_seconds
    assert_equal 2, session.training_session_blocks.first.training_session_exercises.first.training_sets.size

    workout_templates(:balanced).update!(title: "Changed later")
    exercises(:squat).update!(name: "Changed squat")
    workout_blocks(:strength).update!(title: "Changed block")
    exercise_prescriptions(:squat_sets).update!(rep_min: 3, rep_max: 3)

    assert_equal "Balanced training day", session.reload.snapshot_title
    snapshot_block = session.training_session_blocks.first
    snapshot_exercise = snapshot_block.training_session_exercises.first
    assert_equal "Strength", snapshot_block.snapshot_title
    assert_equal "Goblet squat", snapshot_exercise.snapshot_name
    assert_equal 8, snapshot_exercise.snapshot_rep_min
    assert_equal 10, snapshot_exercise.snapshot_rep_max
  end

  test "inline ad hoc snapshots require taxonomy and do not create catalog records" do
    session = TrainingSession.build_ad_hoc(person: people(:one))
    exercise = session.training_session_blocks.first.training_session_exercises.first
    exercise.snapshot_name = "Outdoor walk"
    exercise.snapshot_modality = :cardio
    exercise.snapshot_movement_pattern = :locomotion_cardio

    assert_no_difference "Exercise.count" do
      assert session.save
    end
    assert_nil exercise.exercise_id
  end

  test "catalog selection copies taxonomy into the session snapshot" do
    session = TrainingSession.build_ad_hoc(person: people(:one))
    exercise = session.training_session_blocks.first.training_session_exercises.first
    exercise.exercise = exercises(:bike)

    assert session.valid?
    assert_equal "Stationary bike", exercise.snapshot_name
    assert_equal "cardio", exercise.snapshot_modality
    assert_equal "locomotion_cardio", exercise.snapshot_movement_pattern
  end

  test "inline ad hoc entries reject a bare name without taxonomy" do
    session = TrainingSession.build_ad_hoc(person: people(:one))
    exercise = session.training_session_blocks.first.training_session_exercises.first
    exercise.snapshot_name = "Unstructured name"

    assert_not session.valid?
    assert_includes exercise.errors[:snapshot_modality], "is not included in the list"
    assert_includes exercise.errors[:snapshot_movement_pattern], "is not included in the list"
  end

  test "later catalog deletion preserves the session snapshot" do
    catalog_exercise = households(:home).exercises.create!(
      name: "Temporary walk",
      modality: :cardio,
      movement_pattern: :locomotion_cardio
    )
    session = TrainingSession.build_ad_hoc(person: people(:one))
    performed_exercise = session.training_session_blocks.first.training_session_exercises.first
    performed_exercise.exercise = catalog_exercise
    session.save!

    catalog_exercise.destroy!

    assert_nil performed_exercise.reload.exercise_id
    assert_equal "Temporary walk", performed_exercise.snapshot_name
    assert_equal "cardio", performed_exercise.snapshot_modality
  end

  test "completion requires actual block duration and complete structured performance" do
    session = training_sessions(:in_progress)
    block = session.training_session_blocks.first
    set = block.training_session_exercises.first.training_sets.first
    block.update!(actual_duration_seconds: nil)
    set.update!(completed: true, reps: 8)

    error = assert_raises(ActiveRecord::RecordInvalid) { session.complete! }
    assert_includes error.record.errors.full_messages.join, "requires an actual duration"
  end

  test "strength-only work counts entered block time without set durations" do
    session = training_sessions(:in_progress)
    set = session.training_session_blocks.first.training_session_exercises.first.training_sets.first
    set.update!(completed: true, reps: 8, load_amount: 35, load_unit: :lb)

    session.complete!
    week = TrainingWeek.for(household: households(:home), person: people(:one), date: "2026-07-30")

    assert_equal 65.0, week.metrics.find { |metric| metric.key == :structured_minutes }.actual
    assert_equal 2, week.metrics.find { |metric| metric.key == :strength_sessions }.actual
  end

  test "completion rejects classified time beyond the containing block" do
    session = training_sessions(:in_progress)
    set = session.training_session_blocks.first.training_session_exercises.first.training_sets.first
    set.update!(completed: true, duration_seconds: 901, dose_class: :vigorous)

    error = assert_raises(ActiveRecord::RecordInvalid) { session.complete! }
    assert_includes error.record.errors.full_messages.join, "classified work exceeds"
  end
end
