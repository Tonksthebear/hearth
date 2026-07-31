# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_07_30_223000) do
  create_table "exercise_prescriptions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "dose_class"
    t.string "entry_kind", default: "set", null: false
    t.integer "exercise_id", null: false
    t.text "load_guidance"
    t.text "notes"
    t.integer "position", null: false
    t.integer "rep_max"
    t.integer "rep_min"
    t.integer "rest_seconds"
    t.integer "sets_count", default: 1, null: false
    t.decimal "target_rir", precision: 3, scale: 1
    t.decimal "target_rpe", precision: 3, scale: 1
    t.datetime "updated_at", null: false
    t.integer "work_seconds"
    t.integer "workout_block_id", null: false
    t.index ["exercise_id"], name: "index_exercise_prescriptions_on_exercise_id"
    t.index ["workout_block_id", "position"], name: "index_exercise_prescriptions_on_workout_block_id_and_position", unique: true
    t.index ["workout_block_id"], name: "index_exercise_prescriptions_on_workout_block_id"
    t.check_constraint "dose_class IS NULL OR dose_class IN ('none', 'strength', 'zone2', 'vigorous')", name: "exercise_prescriptions_dose_class"
    t.check_constraint "entry_kind IN ('set', 'interval')", name: "exercise_prescriptions_entry_kind"
    t.check_constraint "position > 0", name: "exercise_prescriptions_positive_position"
    t.check_constraint "sets_count > 0", name: "exercise_prescriptions_positive_sets"
  end

  create_table "exercises", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "equipment"
    t.text "guidance"
    t.integer "household_id", null: false
    t.string "modality", null: false
    t.string "movement_pattern", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["household_id", "name"], name: "index_exercises_on_household_id_and_name", unique: true
    t.index ["household_id"], name: "index_exercises_on_household_id"
    t.check_constraint "modality IN ('strength', 'cardio', 'mobility', 'balance', 'recovery', 'mixed', 'other')", name: "exercises_modality"
    t.check_constraint "movement_pattern IN ('squat', 'hinge', 'lunge', 'horizontal_push', 'vertical_push', 'horizontal_pull', 'vertical_pull', 'carry', 'core', 'locomotion_cardio', 'mobility', 'balance', 'other')", name: "exercises_movement_pattern"
  end

  create_table "habit_check_in_measurements", force: :cascade do |t|
    t.boolean "boolean_value"
    t.datetime "created_at", null: false
    t.integer "duration_value"
    t.integer "habit_check_in_id", null: false
    t.integer "habit_metric_id", null: false
    t.decimal "number_value", precision: 12, scale: 3
    t.time "time_of_day_value"
    t.datetime "updated_at", null: false
    t.index ["habit_check_in_id", "habit_metric_id"], name: "index_habit_measurements_on_check_in_and_metric", unique: true
    t.index ["habit_check_in_id"], name: "index_habit_check_in_measurements_on_habit_check_in_id"
    t.index ["habit_metric_id"], name: "index_habit_check_in_measurements_on_habit_metric_id"
    t.check_constraint "(CASE WHEN habit_check_in_measurements.number_value IS NULL THEN 0 ELSE 1 END) + (CASE WHEN habit_check_in_measurements.duration_value IS NULL THEN 0 ELSE 1 END) + (CASE WHEN habit_check_in_measurements.time_of_day_value IS NULL THEN 0 ELSE 1 END) + (CASE WHEN habit_check_in_measurements.boolean_value IS NULL THEN 0 ELSE 1 END) = 1", name: "habit_measurements_one_typed_value"
    t.check_constraint "duration_value IS NULL OR duration_value >= 0", name: "habit_measurements_nonnegative_duration"
  end

  create_table "habit_check_ins", force: :cascade do |t|
    t.date "checked_on", null: false
    t.datetime "created_at", null: false
    t.text "notes"
    t.integer "person_habit_id", null: false
    t.datetime "updated_at", null: false
    t.index ["person_habit_id", "checked_on"], name: "index_habit_check_ins_on_person_habit_id_and_checked_on", unique: true
    t.index ["person_habit_id"], name: "index_habit_check_ins_on_person_habit_id"
  end

  create_table "habit_metrics", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "habit_id", null: false
    t.string "key", null: false
    t.string "label", null: false
    t.integer "position", null: false
    t.string "unit"
    t.datetime "updated_at", null: false
    t.string "value_type", null: false
    t.index ["habit_id", "key"], name: "index_habit_metrics_on_habit_id_and_key", unique: true
    t.index ["habit_id", "position"], name: "index_habit_metrics_on_habit_id_and_position", unique: true
    t.index ["habit_id"], name: "index_habit_metrics_on_habit_id"
    t.check_constraint "position > 0", name: "habit_metrics_positive_position"
    t.check_constraint "value_type IN ('number', 'duration', 'time_of_day', 'boolean')", name: "habit_metrics_value_type"
  end

  create_table "habits", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.integer "household_id", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["household_id", "name"], name: "index_habits_on_household_id_and_name", unique: true
    t.index ["household_id"], name: "index_habits_on_household_id"
  end

  create_table "households", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "installation_key", default: 1, null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["installation_key"], name: "index_households_on_installation_key", unique: true
    t.check_constraint "installation_key = 1", name: "households_single_installation"
  end

  create_table "meal_logs", force: :cascade do |t|
    t.text "ad_hoc_description"
    t.datetime "created_at", null: false
    t.date "eaten_on", null: false
    t.integer "household_id", null: false
    t.integer "person_id", null: false
    t.integer "recipe_id"
    t.datetime "updated_at", null: false
    t.index ["household_id", "eaten_on"], name: "index_meal_logs_on_household_id_and_eaten_on"
    t.index ["household_id"], name: "index_meal_logs_on_household_id"
    t.index ["person_id", "eaten_on"], name: "index_meal_logs_on_person_id_and_eaten_on"
    t.index ["person_id"], name: "index_meal_logs_on_person_id"
    t.index ["recipe_id"], name: "index_meal_logs_on_recipe_id"
  end

  create_table "people", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "household_id", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.integer "weekly_strength_sessions_target"
    t.integer "weekly_structured_minutes_target"
    t.integer "weekly_vigorous_minutes_target"
    t.integer "weekly_zone2_minutes_target"
    t.index ["household_id"], name: "index_people_on_household_id"
    t.check_constraint "weekly_strength_sessions_target IS NULL OR weekly_strength_sessions_target > 0", name: "people_positive_strength_sessions_target"
    t.check_constraint "weekly_structured_minutes_target IS NULL OR weekly_structured_minutes_target > 0", name: "people_positive_structured_minutes_target"
    t.check_constraint "weekly_vigorous_minutes_target IS NULL OR weekly_vigorous_minutes_target > 0", name: "people_positive_vigorous_minutes_target"
    t.check_constraint "weekly_zone2_minutes_target IS NULL OR weekly_zone2_minutes_target > 0", name: "people_positive_zone2_minutes_target"
  end

  create_table "person_habit_metrics", force: :cascade do |t|
    t.boolean "boolean_value"
    t.datetime "created_at", null: false
    t.integer "duration_value"
    t.integer "habit_metric_id", null: false
    t.decimal "number_value", precision: 12, scale: 3
    t.integer "person_habit_id", null: false
    t.time "time_of_day_value"
    t.datetime "updated_at", null: false
    t.index ["habit_metric_id"], name: "index_person_habit_metrics_on_habit_metric_id"
    t.index ["person_habit_id", "habit_metric_id"], name: "index_person_habit_metrics_on_configuration_and_metric", unique: true
    t.index ["person_habit_id"], name: "index_person_habit_metrics_on_person_habit_id"
    t.check_constraint "(CASE WHEN person_habit_metrics.number_value IS NULL THEN 0 ELSE 1 END) + (CASE WHEN person_habit_metrics.duration_value IS NULL THEN 0 ELSE 1 END) + (CASE WHEN person_habit_metrics.time_of_day_value IS NULL THEN 0 ELSE 1 END) + (CASE WHEN person_habit_metrics.boolean_value IS NULL THEN 0 ELSE 1 END) <= 1", name: "person_habit_metrics_one_typed_value"
    t.check_constraint "duration_value IS NULL OR duration_value >= 0", name: "person_habit_metrics_nonnegative_duration"
  end

  create_table "person_habits", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.boolean "friday", default: true, null: false
    t.integer "habit_id", null: false
    t.boolean "monday", default: true, null: false
    t.integer "person_id", null: false
    t.integer "position", null: false
    t.boolean "saturday", default: true, null: false
    t.boolean "sunday", default: true, null: false
    t.boolean "thursday", default: true, null: false
    t.boolean "tuesday", default: true, null: false
    t.datetime "updated_at", null: false
    t.boolean "wednesday", default: true, null: false
    t.index ["habit_id"], name: "index_person_habits_on_habit_id"
    t.index ["person_id", "habit_id"], name: "index_person_habits_on_person_id_and_habit_id", unique: true
    t.index ["person_id", "position"], name: "index_person_habits_on_person_id_and_position"
    t.index ["person_id"], name: "index_person_habits_on_person_id"
    t.check_constraint "position > 0", name: "person_habits_positive_position"
  end

  create_table "planned_meals", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "household_id", null: false
    t.integer "person_id"
    t.date "planned_on", null: false
    t.integer "recipe_id", null: false
    t.datetime "updated_at", null: false
    t.index ["household_id", "planned_on"], name: "index_planned_meals_on_household_id_and_planned_on"
    t.index ["household_id"], name: "index_planned_meals_on_household_id"
    t.index ["person_id", "planned_on"], name: "index_planned_meals_on_person_id_and_planned_on"
    t.index ["person_id"], name: "index_planned_meals_on_person_id"
    t.index ["recipe_id"], name: "index_planned_meals_on_recipe_id"
  end

  create_table "planned_workouts", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "household_id", null: false
    t.integer "person_id", null: false
    t.date "scheduled_on", null: false
    t.string "skip_reason"
    t.datetime "skipped_at"
    t.integer "training_session_id"
    t.datetime "updated_at", null: false
    t.integer "workout_template_id", null: false
    t.index ["household_id", "scheduled_on"], name: "index_planned_workouts_on_household_id_and_scheduled_on"
    t.index ["household_id"], name: "index_planned_workouts_on_household_id"
    t.index ["person_id", "scheduled_on"], name: "index_planned_workouts_on_person_id_and_scheduled_on"
    t.index ["person_id"], name: "index_planned_workouts_on_person_id"
    t.index ["training_session_id"], name: "index_planned_workouts_on_training_session_id", unique: true
    t.index ["workout_template_id"], name: "index_planned_workouts_on_workout_template_id"
    t.check_constraint "skip_reason IS NULL OR skipped_at IS NOT NULL", name: "planned_workouts_reason_requires_skip"
    t.check_constraint "training_session_id IS NULL OR skipped_at IS NULL", name: "planned_workouts_session_or_skip"
  end

  create_table "recipe_ingredients", force: :cascade do |t|
    t.text "amount"
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.text "notes"
    t.integer "position", null: false
    t.integer "recipe_id", null: false
    t.string "unit"
    t.datetime "updated_at", null: false
    t.index ["recipe_id", "position"], name: "index_recipe_ingredients_on_recipe_id_and_position", unique: true
    t.index ["recipe_id"], name: "index_recipe_ingredients_on_recipe_id"
    t.check_constraint "position > 0", name: "recipe_ingredients_positive_position"
  end

  create_table "recipe_instructions", force: :cascade do |t|
    t.text "body", null: false
    t.datetime "created_at", null: false
    t.integer "position", null: false
    t.integer "recipe_id", null: false
    t.datetime "updated_at", null: false
    t.index ["recipe_id", "position"], name: "index_recipe_instructions_on_recipe_id_and_position", unique: true
    t.index ["recipe_id"], name: "index_recipe_instructions_on_recipe_id"
    t.check_constraint "position > 0", name: "recipe_instructions_positive_position"
  end

  create_table "recipes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.integer "household_id", null: false
    t.string "provenance_status", null: false
    t.string "source_name"
    t.string "source_url"
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.string "yield"
    t.index ["household_id", "provenance_status"], name: "index_recipes_on_household_id_and_provenance_status"
    t.index ["household_id"], name: "index_recipes_on_household_id"
    t.check_constraint "provenance_status IN ('personal', 'verified', 'adapted', 'observed')", name: "recipes_provenance_status"
  end

  create_table "sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.integer "user_id", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "training_session_blocks", force: :cascade do |t|
    t.integer "actual_duration_seconds"
    t.datetime "created_at", null: false
    t.text "notes"
    t.integer "position", null: false
    t.string "snapshot_block_kind", null: false
    t.string "snapshot_dose_class", default: "none", null: false
    t.integer "snapshot_planned_duration_minutes"
    t.string "snapshot_title", null: false
    t.integer "training_session_id", null: false
    t.datetime "updated_at", null: false
    t.index ["training_session_id", "position"], name: "idx_on_training_session_id_position_e41e181bae", unique: true
    t.index ["training_session_id"], name: "index_training_session_blocks_on_training_session_id"
    t.check_constraint "actual_duration_seconds IS NULL OR actual_duration_seconds > 0", name: "training_session_blocks_positive_actual_duration"
    t.check_constraint "position > 0", name: "training_session_blocks_positive_position"
  end

  create_table "training_session_exercises", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "exercise_id"
    t.text "notes"
    t.integer "position", null: false
    t.string "snapshot_dose_class", default: "none", null: false
    t.string "snapshot_entry_kind", default: "set", null: false
    t.text "snapshot_equipment"
    t.text "snapshot_guidance"
    t.text "snapshot_load_guidance"
    t.string "snapshot_modality", null: false
    t.string "snapshot_movement_pattern", null: false
    t.string "snapshot_name", null: false
    t.integer "snapshot_rep_max"
    t.integer "snapshot_rep_min"
    t.integer "snapshot_rest_seconds"
    t.integer "snapshot_sets_count"
    t.decimal "snapshot_target_rir", precision: 3, scale: 1
    t.decimal "snapshot_target_rpe", precision: 3, scale: 1
    t.integer "snapshot_work_seconds"
    t.integer "training_session_block_id", null: false
    t.datetime "updated_at", null: false
    t.index ["exercise_id"], name: "index_training_session_exercises_on_exercise_id"
    t.index ["training_session_block_id", "position"], name: "index_session_exercises_on_block_and_position", unique: true
    t.index ["training_session_block_id"], name: "index_training_session_exercises_on_training_session_block_id"
    t.check_constraint "position > 0", name: "training_session_exercises_positive_position"
  end

  create_table "training_sessions", force: :cascade do |t|
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.integer "household_id", null: false
    t.text "notes"
    t.date "performed_on", null: false
    t.integer "person_id", null: false
    t.string "snapshot_provenance_status"
    t.string "snapshot_source_name"
    t.string "snapshot_source_url"
    t.string "snapshot_title", null: false
    t.datetime "started_at", null: false
    t.datetime "updated_at", null: false
    t.integer "workout_template_id"
    t.index ["household_id"], name: "index_training_sessions_on_household_id"
    t.index ["person_id", "performed_on"], name: "index_training_sessions_on_person_id_and_performed_on"
    t.index ["person_id"], name: "index_training_sessions_on_person_id"
    t.index ["workout_template_id"], name: "index_training_sessions_on_workout_template_id"
  end

  create_table "training_sets", force: :cascade do |t|
    t.boolean "completed", default: false, null: false
    t.datetime "created_at", null: false
    t.decimal "distance_amount", precision: 10, scale: 2
    t.string "distance_unit"
    t.string "dose_class", default: "none", null: false
    t.integer "duration_seconds"
    t.string "entry_kind", default: "set", null: false
    t.decimal "load_amount", precision: 8, scale: 2
    t.string "load_unit"
    t.text "notes"
    t.integer "position", null: false
    t.integer "reps"
    t.decimal "rir", precision: 3, scale: 1
    t.decimal "rpe", precision: 3, scale: 1
    t.integer "training_session_exercise_id", null: false
    t.datetime "updated_at", null: false
    t.index ["training_session_exercise_id", "position"], name: "index_training_sets_on_exercise_and_position", unique: true
    t.index ["training_session_exercise_id"], name: "index_training_sets_on_training_session_exercise_id"
    t.check_constraint "distance_unit IS NULL OR distance_unit IN ('m', 'km', 'mi', 'ft')", name: "training_sets_distance_unit"
    t.check_constraint "dose_class IN ('none', 'strength', 'zone2', 'vigorous')", name: "training_sets_dose_class"
    t.check_constraint "entry_kind IN ('set', 'interval')", name: "training_sets_entry_kind"
    t.check_constraint "load_unit IS NULL OR load_unit IN ('lb', 'kg')", name: "training_sets_load_unit"
    t.check_constraint "position > 0", name: "training_sets_positive_position"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email_address", null: false
    t.string "password_digest", null: false
    t.integer "person_id", null: false
    t.datetime "updated_at", null: false
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
    t.index ["person_id"], name: "index_users_on_person_id", unique: true
  end

  create_table "workout_blocks", force: :cascade do |t|
    t.string "block_kind", null: false
    t.datetime "created_at", null: false
    t.string "dose_class", default: "none", null: false
    t.text "notes"
    t.integer "planned_duration_minutes"
    t.integer "position", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.integer "workout_template_id", null: false
    t.index ["workout_template_id", "position"], name: "index_workout_blocks_on_workout_template_id_and_position", unique: true
    t.index ["workout_template_id"], name: "index_workout_blocks_on_workout_template_id"
    t.check_constraint "block_kind IN ('warm_up', 'strength', 'zone2', 'hiit_interval', 'mobility', 'cooldown_recovery', 'other')", name: "workout_blocks_block_kind"
    t.check_constraint "dose_class IN ('none', 'strength', 'zone2', 'vigorous')", name: "workout_blocks_dose_class"
    t.check_constraint "planned_duration_minutes IS NULL OR planned_duration_minutes > 0", name: "workout_blocks_positive_duration"
    t.check_constraint "position > 0", name: "workout_blocks_positive_position"
  end

  create_table "workout_templates", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.integer "household_id", null: false
    t.string "provenance_status", null: false
    t.string "source_name"
    t.string "source_url"
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["household_id", "provenance_status"], name: "index_workout_templates_on_household_id_and_provenance_status"
    t.index ["household_id"], name: "index_workout_templates_on_household_id"
    t.check_constraint "provenance_status IN ('verified', 'adapted', 'observed', 'personal')", name: "workout_templates_provenance_status"
  end

  add_foreign_key "exercise_prescriptions", "exercises", on_delete: :restrict
  add_foreign_key "exercise_prescriptions", "workout_blocks"
  add_foreign_key "exercises", "households"
  add_foreign_key "habit_check_in_measurements", "habit_check_ins"
  add_foreign_key "habit_check_in_measurements", "habit_metrics"
  add_foreign_key "habit_check_ins", "person_habits"
  add_foreign_key "habit_metrics", "habits"
  add_foreign_key "habits", "households"
  add_foreign_key "meal_logs", "households"
  add_foreign_key "meal_logs", "people"
  add_foreign_key "meal_logs", "recipes"
  add_foreign_key "people", "households"
  add_foreign_key "person_habit_metrics", "habit_metrics"
  add_foreign_key "person_habit_metrics", "person_habits"
  add_foreign_key "person_habits", "habits"
  add_foreign_key "person_habits", "people"
  add_foreign_key "planned_meals", "households"
  add_foreign_key "planned_meals", "people"
  add_foreign_key "planned_meals", "recipes"
  add_foreign_key "planned_workouts", "households"
  add_foreign_key "planned_workouts", "people"
  add_foreign_key "planned_workouts", "training_sessions", on_delete: :nullify
  add_foreign_key "planned_workouts", "workout_templates"
  add_foreign_key "recipe_ingredients", "recipes"
  add_foreign_key "recipe_instructions", "recipes"
  add_foreign_key "recipes", "households"
  add_foreign_key "sessions", "users"
  add_foreign_key "training_session_blocks", "training_sessions"
  add_foreign_key "training_session_exercises", "exercises", on_delete: :nullify
  add_foreign_key "training_session_exercises", "training_session_blocks"
  add_foreign_key "training_sessions", "households"
  add_foreign_key "training_sessions", "people"
  add_foreign_key "training_sessions", "workout_templates", on_delete: :nullify
  add_foreign_key "training_sets", "training_session_exercises"
  add_foreign_key "users", "people"
  add_foreign_key "workout_blocks", "workout_templates"
  add_foreign_key "workout_templates", "households"
end
