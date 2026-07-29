class CreateTrainingDomain < ActiveRecord::Migration[8.1]
  def change
    create_table :exercises do |t|
      t.references :household, null: false, foreign_key: true
      t.string :name, null: false
      t.string :modality, null: false
      t.string :movement_pattern, null: false
      t.text :equipment
      t.text :guidance
      t.timestamps
    end
    add_index :exercises, %i[ household_id name ], unique: true
    add_check_constraint :exercises,
      "modality IN ('strength', 'cardio', 'mobility', 'balance', 'recovery', 'mixed', 'other')",
      name: "exercises_modality"
    add_check_constraint :exercises,
      "movement_pattern IN ('squat', 'hinge', 'lunge', 'horizontal_push', 'vertical_push', 'horizontal_pull', 'vertical_pull', 'carry', 'core', 'locomotion_cardio', 'mobility', 'balance', 'other')",
      name: "exercises_movement_pattern"

    create_table :workout_templates do |t|
      t.references :household, null: false, foreign_key: true
      t.string :title, null: false
      t.text :description
      t.string :provenance_status, null: false
      t.string :source_name
      t.string :source_url
      t.timestamps
    end
    add_index :workout_templates, %i[ household_id provenance_status ]
    add_check_constraint :workout_templates,
      "provenance_status IN ('verified', 'adapted', 'observed', 'personal')",
      name: "workout_templates_provenance_status"

    create_table :workout_blocks do |t|
      t.references :workout_template, null: false, foreign_key: true
      t.integer :position, null: false
      t.string :title, null: false
      t.string :block_kind, null: false
      t.string :dose_class, null: false, default: "none"
      t.integer :planned_duration_minutes
      t.text :notes
      t.timestamps
    end
    add_index :workout_blocks, %i[ workout_template_id position ], unique: true
    add_check_constraint :workout_blocks, "position > 0", name: "workout_blocks_positive_position"
    add_check_constraint :workout_blocks,
      "block_kind IN ('warm_up', 'strength', 'zone2', 'hiit_interval', 'mobility', 'cooldown_recovery', 'other')",
      name: "workout_blocks_block_kind"
    add_check_constraint :workout_blocks,
      "dose_class IN ('none', 'strength', 'zone2', 'vigorous')",
      name: "workout_blocks_dose_class"
    add_check_constraint :workout_blocks,
      "planned_duration_minutes IS NULL OR planned_duration_minutes > 0",
      name: "workout_blocks_positive_duration"

    create_table :exercise_prescriptions do |t|
      t.references :workout_block, null: false, foreign_key: true
      t.references :exercise, null: false, foreign_key: { on_delete: :restrict }
      t.integer :position, null: false
      t.string :entry_kind, null: false, default: "set"
      t.integer :sets_count, null: false, default: 1
      t.integer :rep_min
      t.integer :rep_max
      t.integer :work_seconds
      t.integer :rest_seconds
      t.decimal :target_rpe, precision: 3, scale: 1
      t.decimal :target_rir, precision: 3, scale: 1
      t.text :load_guidance
      t.string :dose_class
      t.text :notes
      t.timestamps
    end
    add_index :exercise_prescriptions, %i[ workout_block_id position ], unique: true
    add_check_constraint :exercise_prescriptions, "position > 0", name: "exercise_prescriptions_positive_position"
    add_check_constraint :exercise_prescriptions, "sets_count > 0", name: "exercise_prescriptions_positive_sets"
    add_check_constraint :exercise_prescriptions,
      "entry_kind IN ('set', 'interval')",
      name: "exercise_prescriptions_entry_kind"
    add_check_constraint :exercise_prescriptions,
      "dose_class IS NULL OR dose_class IN ('none', 'strength', 'zone2', 'vigorous')",
      name: "exercise_prescriptions_dose_class"

    create_table :training_sessions do |t|
      t.references :household, null: false, foreign_key: true
      t.references :person, null: false, foreign_key: true
      t.references :workout_template, foreign_key: { on_delete: :nullify }
      t.string :snapshot_title, null: false
      t.string :snapshot_provenance_status
      t.string :snapshot_source_name
      t.string :snapshot_source_url
      t.date :performed_on, null: false
      t.datetime :started_at, null: false
      t.datetime :completed_at
      t.text :notes
      t.timestamps
    end
    add_index :training_sessions, %i[ person_id performed_on ]

    create_table :training_session_blocks do |t|
      t.references :training_session, null: false, foreign_key: true
      t.integer :position, null: false
      t.string :snapshot_title, null: false
      t.string :snapshot_block_kind, null: false
      t.string :snapshot_dose_class, null: false, default: "none"
      t.integer :snapshot_planned_duration_minutes
      t.integer :actual_duration_seconds
      t.text :notes
      t.timestamps
    end
    add_index :training_session_blocks, %i[ training_session_id position ], unique: true
    add_check_constraint :training_session_blocks, "position > 0", name: "training_session_blocks_positive_position"
    add_check_constraint :training_session_blocks,
      "actual_duration_seconds IS NULL OR actual_duration_seconds > 0",
      name: "training_session_blocks_positive_actual_duration"

    create_table :training_session_exercises do |t|
      t.references :training_session_block, null: false, foreign_key: true
      t.references :exercise, foreign_key: { on_delete: :nullify }
      t.integer :position, null: false
      t.string :snapshot_name, null: false
      t.string :snapshot_modality, null: false
      t.string :snapshot_movement_pattern, null: false
      t.text :snapshot_equipment
      t.text :snapshot_guidance
      t.string :snapshot_entry_kind, null: false, default: "set"
      t.string :snapshot_dose_class, null: false, default: "none"
      t.integer :snapshot_sets_count
      t.integer :snapshot_rep_min
      t.integer :snapshot_rep_max
      t.integer :snapshot_work_seconds
      t.integer :snapshot_rest_seconds
      t.decimal :snapshot_target_rpe, precision: 3, scale: 1
      t.decimal :snapshot_target_rir, precision: 3, scale: 1
      t.text :snapshot_load_guidance
      t.text :notes
      t.timestamps
    end
    add_index :training_session_exercises, %i[ training_session_block_id position ], unique: true,
      name: "index_session_exercises_on_block_and_position"
    add_check_constraint :training_session_exercises, "position > 0",
      name: "training_session_exercises_positive_position"

    create_table :training_sets do |t|
      t.references :training_session_exercise, null: false, foreign_key: true
      t.integer :position, null: false
      t.string :entry_kind, null: false, default: "set"
      t.string :dose_class, null: false, default: "none"
      t.integer :reps
      t.decimal :load_amount, precision: 8, scale: 2
      t.string :load_unit
      t.integer :duration_seconds
      t.decimal :distance_amount, precision: 10, scale: 2
      t.string :distance_unit
      t.decimal :rpe, precision: 3, scale: 1
      t.decimal :rir, precision: 3, scale: 1
      t.boolean :completed, null: false, default: false
      t.text :notes
      t.timestamps
    end
    add_index :training_sets, %i[ training_session_exercise_id position ], unique: true,
      name: "index_training_sets_on_exercise_and_position"
    add_check_constraint :training_sets, "position > 0", name: "training_sets_positive_position"
    add_check_constraint :training_sets, "entry_kind IN ('set', 'interval')", name: "training_sets_entry_kind"
    add_check_constraint :training_sets,
      "dose_class IN ('none', 'strength', 'zone2', 'vigorous')",
      name: "training_sets_dose_class"
    add_check_constraint :training_sets,
      "load_unit IS NULL OR load_unit IN ('lb', 'kg')",
      name: "training_sets_load_unit"
    add_check_constraint :training_sets,
      "distance_unit IS NULL OR distance_unit IN ('m', 'km', 'mi', 'ft')",
      name: "training_sets_distance_unit"

    change_table :people, bulk: true do |t|
      t.integer :weekly_structured_minutes_target
      t.integer :weekly_strength_sessions_target
      t.integer :weekly_zone2_minutes_target
      t.integer :weekly_vigorous_minutes_target
    end
    add_check_constraint :people,
      "weekly_structured_minutes_target IS NULL OR weekly_structured_minutes_target > 0",
      name: "people_positive_structured_minutes_target"
    add_check_constraint :people,
      "weekly_strength_sessions_target IS NULL OR weekly_strength_sessions_target > 0",
      name: "people_positive_strength_sessions_target"
    add_check_constraint :people,
      "weekly_zone2_minutes_target IS NULL OR weekly_zone2_minutes_target > 0",
      name: "people_positive_zone2_minutes_target"
    add_check_constraint :people,
      "weekly_vigorous_minutes_target IS NULL OR weekly_vigorous_minutes_target > 0",
      name: "people_positive_vigorous_minutes_target"
  end
end
