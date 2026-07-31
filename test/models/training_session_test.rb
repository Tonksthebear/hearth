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
    assert_equal "reps", snapshot_exercise.snapshot_performance_kind
    assert_predicate snapshot_exercise, :snapshot_per_side?
    assert_equal "3 sec lowering", snapshot_exercise.snapshot_tempo_cue
    assert_equal 120, snapshot_exercise.snapshot_target_heart_rate_min
    assert_equal 150, snapshot_exercise.snapshot_target_heart_rate_max
    assert_equal "bpm", snapshot_exercise.snapshot_target_heart_rate_unit
  end

  test "inline ad hoc snapshots require taxonomy and do not create catalog records" do
    session = TrainingSession.build_ad_hoc(person: people(:one))
    exercise = session.training_session_blocks.first.training_session_exercises.first
    exercise.snapshot_name = "Outdoor walk"
    exercise.snapshot_modality = :cardio
    exercise.snapshot_movement_pattern = :locomotion_cardio
    exercise.snapshot_rep_min = 1

    assert_no_difference "Exercise.count" do
      assert session.save
    end
    assert_nil exercise.exercise_id
  end

  test "catalog selection copies taxonomy into the session snapshot" do
    session = TrainingSession.build_ad_hoc(person: people(:one))
    exercise = session.training_session_blocks.first.training_session_exercises.first
    exercise.exercise = exercises(:bike)
    exercise.snapshot_rep_min = 1

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
    performed_exercise.snapshot_rep_min = 1
    session.save!

    catalog_exercise.destroy!

    assert_nil performed_exercise.reload.exercise_id
    assert_equal "Temporary walk", performed_exercise.snapshot_name
    assert_equal "cardio", performed_exercise.snapshot_modality
  end

  test "starting a template prefills secondary duration for distance and count work" do
    template = households(:home).workout_templates.create!(title: "Measured work", provenance_status: :personal)
    block = template.workout_blocks.create!(
      position: 1,
      title: "Conditioning",
      block_kind: :zone2,
      dose_class: :zone2,
      planned_duration_minutes: 20
    )
    block.exercise_prescriptions.create!(
      exercise: exercises(:bike),
      position: 1,
      performance_kind: :distance,
      sets_count: 1,
      work_seconds: 600,
      target_distance_amount: 5,
      target_distance_unit: :km
    )
    block.exercise_prescriptions.create!(
      exercise: exercises(:squat),
      position: 2,
      performance_kind: :count,
      sets_count: 1,
      work_seconds: 300,
      target_count: 40,
      target_count_unit: :steps
    )

    session = TrainingSession.start_from(template: template, person: people(:one))

    assert_equal [ 600, 300 ], session.training_session_blocks.first.training_session_exercises.map { |exercise| exercise.training_sets.sole.duration_seconds }
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
    exercise = session.training_session_blocks.first.training_session_exercises.first
    exercise.update!(snapshot_performance_kind: :duration, snapshot_work_seconds: 901)
    set = exercise.training_sets.first
    set.update!(completed: true, duration_seconds: 901, dose_class: :vigorous)

    error = assert_raises(ActiveRecord::RecordInvalid) { session.complete! }
    assert_includes error.record.errors.full_messages.join, "classified work exceeds"
  end
end
