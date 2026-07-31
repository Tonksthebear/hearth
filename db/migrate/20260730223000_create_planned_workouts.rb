class CreatePlannedWorkouts < ActiveRecord::Migration[8.1]
  def change
    create_table :planned_workouts do |t|
      t.references :household, null: false, foreign_key: true
      t.references :person, null: false, foreign_key: true
      t.references :workout_template, null: false, foreign_key: true
      t.references :training_session, foreign_key: { on_delete: :nullify }, index: { unique: true }
      t.date :scheduled_on, null: false
      t.datetime :skipped_at
      t.string :skip_reason

      t.timestamps
    end

    add_index :planned_workouts, [ :household_id, :scheduled_on ]
    add_index :planned_workouts, [ :person_id, :scheduled_on ]
    add_check_constraint :planned_workouts,
      "skip_reason IS NULL OR skipped_at IS NOT NULL",
      name: "planned_workouts_reason_requires_skip"
    add_check_constraint :planned_workouts,
      "training_session_id IS NULL OR skipped_at IS NULL",
      name: "planned_workouts_session_or_skip"
  end
end
