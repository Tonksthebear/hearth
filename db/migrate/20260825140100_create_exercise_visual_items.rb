class CreateExerciseVisualItems < ActiveRecord::Migration[8.1]
  def change
    create_table :exercise_visual_items do |t|
      t.references :exercise_visual, null: false, foreign_key: true
      t.integer :position, null: false
      t.string :source_identifier
      t.string :source_checksum
      t.json :source_metadata, null: false, default: {}

      t.timestamps
    end

    add_index :exercise_visual_items, [ :exercise_visual_id, :position ], unique: true

    add_check_constraint :exercise_visual_items, "position > 0", name: "exercise_visual_items_positive_position"
  end
end
