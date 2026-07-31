require "test_helper"
require Rails.root.join("db/migrate/20260731120001_expand_training_performance_capture")

class ExpandTrainingPerformanceCaptureTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  test "backfills legacy primary kinds before removing entry kind columns" do
    connection = ActiveRecord::Base.connection
    migration = ExpandTrainingPerformanceCapture.new
    block_id = workout_blocks(:strength).id
    exercise_id = exercises(:bike).id
    session_block_id = training_session_blocks(:draft_block).id
    now = connection.quote(Time.current)
    legacy_kind = [ "entry", "kind" ].join("_")
    legacy_snapshot_kind = [ "snapshot", legacy_kind ].join("_")

    migration.down

    connection.execute <<~SQL.squish
      INSERT INTO exercise_prescriptions
        (workout_block_id, exercise_id, position, #{legacy_kind}, sets_count, work_seconds, created_at, updated_at)
      VALUES (#{block_id}, #{exercise_id}, 2, 'set', 1, 45, #{now}, #{now})
    SQL
    duration_id = connection.select_value("SELECT last_insert_rowid()")
    connection.execute <<~SQL.squish
      INSERT INTO exercise_prescriptions
        (workout_block_id, exercise_id, position, #{legacy_kind}, sets_count, created_at, updated_at)
      VALUES (#{block_id}, #{exercise_id}, 3, 'set', 1, #{now}, #{now})
    SQL
    empty_id = connection.select_value("SELECT last_insert_rowid()")

    connection.execute <<~SQL.squish
      INSERT INTO training_session_exercises
        (training_session_block_id, position, snapshot_name, snapshot_modality,
         snapshot_movement_pattern, #{legacy_snapshot_kind}, snapshot_dose_class,
         created_at, updated_at)
      VALUES (#{session_block_id}, 2, 'Legacy distance', 'cardio',
              'locomotion_cardio', 'set', 'none', #{now}, #{now})
    SQL
    distance_exercise_id = connection.select_value("SELECT last_insert_rowid()")
    connection.execute <<~SQL.squish
      INSERT INTO training_sets
        (training_session_exercise_id, position, #{legacy_kind}, dose_class,
         distance_amount, distance_unit, completed, created_at, updated_at)
      VALUES (#{distance_exercise_id}, 1, 'set', 'none', 1.0, 'mi', 0, #{now}, #{now})
    SQL

    migration.up

    assert_equal "duration", connection.select_value("SELECT performance_kind FROM exercise_prescriptions WHERE id = #{duration_id}")
    assert_equal "reps", connection.select_value("SELECT performance_kind FROM exercise_prescriptions WHERE id = #{empty_id}")
    assert_equal "distance", connection.select_value("SELECT snapshot_performance_kind FROM training_session_exercises WHERE id = #{distance_exercise_id}")
    assert_not connection.column_exists?(:exercise_prescriptions, legacy_kind)
    assert_not connection.column_exists?(:training_session_exercises, legacy_snapshot_kind)
    assert_not connection.column_exists?(:training_sets, legacy_kind)
  ensure
    migration.up if connection.column_exists?(:exercise_prescriptions, legacy_kind)
    [ ExercisePrescription, TrainingSessionExercise, TrainingSet ].each(&:reset_column_information)
  end
end
