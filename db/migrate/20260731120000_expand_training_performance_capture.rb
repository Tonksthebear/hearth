class ExpandTrainingPerformanceCapture < ActiveRecord::Migration[8.1]
  PERFORMANCE_KINDS = %w[reps duration distance count interval].freeze
  DISTANCE_UNITS = %w[m km mi ft].freeze
  COUNT_UNITS = %w[laps flights steps].freeze
  HEART_RATE_UNITS = %w[bpm percent_max].freeze

  def up
    change_table :exercise_prescriptions, bulk: true do |t|
      t.string :performance_kind
      t.decimal :target_distance_amount, precision: 10, scale: 2
      t.string :target_distance_unit
      t.integer :target_count
      t.string :target_count_unit
      t.boolean :per_side, null: false, default: false
      t.string :tempo_cue
      t.integer :target_heart_rate_min
      t.integer :target_heart_rate_max
      t.string :target_heart_rate_unit
    end

    change_table :training_session_exercises, bulk: true do |t|
      t.string :snapshot_performance_kind
      t.decimal :snapshot_target_distance_amount, precision: 10, scale: 2
      t.string :snapshot_target_distance_unit
      t.integer :snapshot_target_count
      t.string :snapshot_target_count_unit
      t.boolean :snapshot_per_side, null: false, default: false
      t.string :snapshot_tempo_cue
      t.integer :snapshot_target_heart_rate_min
      t.integer :snapshot_target_heart_rate_max
      t.string :snapshot_target_heart_rate_unit
      t.datetime :completed_at
      t.string :difficulty
      t.text :soreness_or_pain
      t.text :substitution
      t.text :next_time_adjustment
    end

    change_table :training_sets, bulk: true do |t|
      t.integer :count
      t.string :count_unit
      t.integer :rest_seconds
      t.integer :average_heart_rate_bpm
      t.integer :peak_heart_rate_bpm
    end

    execute <<~SQL.squish
      UPDATE exercise_prescriptions
      SET performance_kind = CASE
        WHEN entry_kind = 'interval' THEN 'interval'
        WHEN rep_min IS NOT NULL OR rep_max IS NOT NULL THEN 'reps'
        WHEN work_seconds IS NOT NULL THEN 'duration'
        ELSE 'reps'
      END
    SQL

    execute <<~SQL.squish
      UPDATE training_session_exercises
      SET snapshot_performance_kind = CASE
        WHEN snapshot_entry_kind = 'interval' THEN 'interval'
        WHEN snapshot_rep_min IS NOT NULL OR snapshot_rep_max IS NOT NULL THEN 'reps'
        WHEN snapshot_work_seconds IS NOT NULL THEN 'duration'
        WHEN EXISTS (
          SELECT 1 FROM training_sets
          WHERE training_sets.training_session_exercise_id = training_session_exercises.id
            AND training_sets.reps IS NOT NULL
        ) THEN 'reps'
        WHEN EXISTS (
          SELECT 1 FROM training_sets
          WHERE training_sets.training_session_exercise_id = training_session_exercises.id
            AND training_sets.duration_seconds IS NOT NULL
        ) THEN 'duration'
        WHEN EXISTS (
          SELECT 1 FROM training_sets
          WHERE training_sets.training_session_exercise_id = training_session_exercises.id
            AND training_sets.distance_amount IS NOT NULL
        ) THEN 'distance'
        ELSE 'reps'
      END
    SQL

    execute "UPDATE training_sets SET rest_seconds = 0 WHERE entry_kind = 'interval' AND rest_seconds IS NULL"

    change_column_null :exercise_prescriptions, :performance_kind, false
    change_column_default :exercise_prescriptions, :performance_kind, "reps"
    change_column_null :training_session_exercises, :snapshot_performance_kind, false
    change_column_default :training_session_exercises, :snapshot_performance_kind, "reps"

    add_check_constraint :exercise_prescriptions,
      "performance_kind IN ('#{PERFORMANCE_KINDS.join("', '")}')",
      name: "exercise_prescriptions_performance_kind"
    add_check_constraint :exercise_prescriptions,
      "target_distance_unit IS NULL OR target_distance_unit IN ('#{DISTANCE_UNITS.join("', '")}')",
      name: "exercise_prescriptions_target_distance_unit"
    add_check_constraint :exercise_prescriptions,
      "target_count_unit IS NULL OR target_count_unit IN ('#{COUNT_UNITS.join("', '")}')",
      name: "exercise_prescriptions_target_count_unit"
    add_check_constraint :exercise_prescriptions,
      "target_heart_rate_unit IS NULL OR target_heart_rate_unit IN ('#{HEART_RATE_UNITS.join("', '")}')",
      name: "exercise_prescriptions_target_heart_rate_unit"
    add_check_constraint :training_session_exercises,
      "snapshot_performance_kind IN ('#{PERFORMANCE_KINDS.join("', '")}')",
      name: "training_session_exercises_performance_kind"
    add_check_constraint :training_session_exercises,
      "snapshot_target_distance_unit IS NULL OR snapshot_target_distance_unit IN ('#{DISTANCE_UNITS.join("', '")}')",
      name: "training_session_exercises_target_distance_unit"
    add_check_constraint :training_session_exercises,
      "snapshot_target_count_unit IS NULL OR snapshot_target_count_unit IN ('#{COUNT_UNITS.join("', '")}')",
      name: "training_session_exercises_target_count_unit"
    add_check_constraint :training_session_exercises,
      "snapshot_target_heart_rate_unit IS NULL OR snapshot_target_heart_rate_unit IN ('#{HEART_RATE_UNITS.join("', '")}')",
      name: "training_session_exercises_target_heart_rate_unit"
    add_check_constraint :training_session_exercises,
      "difficulty IS NULL OR difficulty IN ('too_easy', 'about_right', 'too_hard')",
      name: "training_session_exercises_difficulty"
    add_check_constraint :training_sets,
      "count_unit IS NULL OR count_unit IN ('#{COUNT_UNITS.join("', '")}')",
      name: "training_sets_count_unit"

    remove_check_constraint :exercise_prescriptions, name: "exercise_prescriptions_entry_kind"
    remove_check_constraint :training_sets, name: "training_sets_entry_kind"
    remove_column :exercise_prescriptions, :entry_kind
    remove_column :training_session_exercises, :snapshot_entry_kind
    remove_column :training_sets, :entry_kind
  end

  def down
    add_column :exercise_prescriptions, :entry_kind, :string, null: false, default: "set"
    add_column :training_session_exercises, :snapshot_entry_kind, :string, null: false, default: "set"
    add_column :training_sets, :entry_kind, :string, null: false, default: "set"

    execute "UPDATE exercise_prescriptions SET entry_kind = CASE WHEN performance_kind = 'interval' THEN 'interval' ELSE 'set' END"
    execute "UPDATE training_session_exercises SET snapshot_entry_kind = CASE WHEN snapshot_performance_kind = 'interval' THEN 'interval' ELSE 'set' END"
    execute <<~SQL.squish
      UPDATE training_sets
      SET entry_kind = CASE
        WHEN training_session_exercise_id IN (
          SELECT id FROM training_session_exercises WHERE snapshot_performance_kind = 'interval'
        ) THEN 'interval'
        ELSE 'set'
      END
    SQL

    add_check_constraint :exercise_prescriptions,
      "entry_kind IN ('set', 'interval')",
      name: "exercise_prescriptions_entry_kind"
    add_check_constraint :training_sets,
      "entry_kind IN ('set', 'interval')",
      name: "training_sets_entry_kind"

    remove_check_constraint :exercise_prescriptions, name: "exercise_prescriptions_performance_kind"
    remove_check_constraint :exercise_prescriptions, name: "exercise_prescriptions_target_distance_unit"
    remove_check_constraint :exercise_prescriptions, name: "exercise_prescriptions_target_count_unit"
    remove_check_constraint :exercise_prescriptions, name: "exercise_prescriptions_target_heart_rate_unit"
    remove_check_constraint :training_session_exercises, name: "training_session_exercises_performance_kind"
    remove_check_constraint :training_session_exercises, name: "training_session_exercises_target_distance_unit"
    remove_check_constraint :training_session_exercises, name: "training_session_exercises_target_count_unit"
    remove_check_constraint :training_session_exercises, name: "training_session_exercises_target_heart_rate_unit"
    remove_check_constraint :training_session_exercises, name: "training_session_exercises_difficulty"
    remove_check_constraint :training_sets, name: "training_sets_count_unit"

    remove_columns :exercise_prescriptions,
      :performance_kind, :target_distance_amount, :target_distance_unit,
      :target_count, :target_count_unit, :per_side, :tempo_cue,
      :target_heart_rate_min, :target_heart_rate_max, :target_heart_rate_unit
    remove_columns :training_session_exercises,
      :snapshot_performance_kind, :snapshot_target_distance_amount,
      :snapshot_target_distance_unit, :snapshot_target_count,
      :snapshot_target_count_unit, :snapshot_per_side, :snapshot_tempo_cue,
      :snapshot_target_heart_rate_min, :snapshot_target_heart_rate_max,
      :snapshot_target_heart_rate_unit, :completed_at, :difficulty,
      :soreness_or_pain, :substitution, :next_time_adjustment
    remove_columns :training_sets,
      :count, :count_unit, :rest_seconds,
      :average_heart_rate_bpm, :peak_heart_rate_bpm
  end
end
