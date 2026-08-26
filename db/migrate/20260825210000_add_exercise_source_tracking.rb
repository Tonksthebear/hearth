class AddExerciseSourceTracking < ActiveRecord::Migration[8.1]
  def change
    add_column :exercises, :source_key, :string
    add_column :exercises, :source_version, :string
    add_column :exercises, :source_snapshot, :json, null: false, default: {}
    add_column :exercises, :source_removed_at, :datetime

    add_index :exercises, [ :household_id, :source_key ],
      unique: true,
      where: "source_key IS NOT NULL",
      name: "index_exercises_on_household_id_and_source_key"
  end
end
