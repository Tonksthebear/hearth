class CreateExerciseVisuals < ActiveRecord::Migration[8.1]
  def change
    create_table :exercise_visuals do |t|
      t.references :exercise, null: false, foreign_key: true
      t.string :kind, null: false
      t.integer :position, null: false
      t.integer :frame_interval_ms
      t.string :alt_text, null: false
      t.text :caption
      t.text :display_attribution
      t.string :provenance_status, null: false, default: "personal"
      t.string :source_key

      t.timestamps
    end

    add_index :exercise_visuals, [ :exercise_id, :position ], unique: true
    add_index :exercise_visuals, [ :exercise_id, :source_key ], unique: true, where: "source_key IS NOT NULL"

    add_check_constraint :exercise_visuals, "position > 0", name: "exercise_visuals_positive_position"
    add_check_constraint :exercise_visuals, "kind IN ('image', 'frame_sequence', 'video')", name: "exercise_visuals_kind"
    add_check_constraint :exercise_visuals,
      "provenance_status IN ('personal', 'verified', 'adapted', 'observed')",
      name: "exercise_visuals_provenance_status"
    add_check_constraint :exercise_visuals,
      "(kind = 'frame_sequence' AND frame_interval_ms IS NOT NULL AND frame_interval_ms BETWEEN 100 AND 5000) OR (kind <> 'frame_sequence' AND frame_interval_ms IS NULL)",
      name: "exercise_visuals_frame_interval_ms"
    add_check_constraint :exercise_visuals, "length(trim(alt_text)) > 0", name: "exercise_visuals_present_alt_text"
  end
end
