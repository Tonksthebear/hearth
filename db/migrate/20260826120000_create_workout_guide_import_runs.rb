class CreateWorkoutGuideImportRuns < ActiveRecord::Migration[8.1]
  def change
    create_table :workout_guide_import_runs do |t|
      t.references :household, null: false, foreign_key: true
      t.string :status, null: false
      t.json :counts, null: false, default: {}
      t.json :skipped, null: false, default: []
      t.json :failures, null: false, default: []
      t.json :details, null: false, default: []
      t.datetime :started_at
      t.datetime :finished_at
      t.timestamps
    end

    add_index :workout_guide_import_runs, :household_id,
      unique: true,
      where: "status IN ('queued', 'running')",
      name: "index_workout_guide_import_runs_active_household"

    add_check_constraint :workout_guide_import_runs,
      "status IN ('queued', 'running', 'completed', 'failed')",
      name: "workout_guide_import_runs_status"
  end
end
