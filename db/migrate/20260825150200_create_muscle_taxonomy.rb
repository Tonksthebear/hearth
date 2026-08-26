class CreateMuscleTaxonomy < ActiveRecord::Migration[8.1]
  DEFAULT_MUSCLES = [
    { key: "trapezius", name: "Trapezius", muscle_group: "back", aliases: [], display_position: 1 },
    { key: "shoulders", name: "Shoulders", muscle_group: "shoulders", aliases: [ "Shoulders" ], display_position: 2 },
    { key: "rear_delts", name: "Rear delts", muscle_group: "shoulders", aliases: [ "Rear Delts" ], display_position: 3 },
    { key: "chest", name: "Chest", muscle_group: "chest", aliases: [ "Chest" ], display_position: 4 },
    { key: "rhomboids", name: "Rhomboids", muscle_group: "back", aliases: [], display_position: 5 },
    { key: "lats", name: "Lats", muscle_group: "back", aliases: [ "Lats" ], display_position: 6 },
    { key: "biceps", name: "Biceps", muscle_group: "arms", aliases: [ "Biceps" ], display_position: 7 },
    { key: "triceps", name: "Triceps", muscle_group: "arms", aliases: [ "Triceps" ], display_position: 8 },
    { key: "forearms", name: "Forearms", muscle_group: "arms", aliases: [ "Forearms" ], display_position: 9 },
    { key: "rectus_abdominis", name: "Rectus abdominis", muscle_group: "core", aliases: [], display_position: 10 },
    { key: "obliques", name: "Obliques", muscle_group: "core", aliases: [], display_position: 11 },
    { key: "erector_spinae", name: "Erector spinae", muscle_group: "back", aliases: [], display_position: 12 },
    { key: "hip_flexors", name: "Hip flexors", muscle_group: "hips", aliases: [], display_position: 13 },
    { key: "groin", name: "Groin", muscle_group: "hips", aliases: [ "Groin" ], display_position: 14 },
    { key: "adductors", name: "Adductors", muscle_group: "hips", aliases: [ "Adductors" ], display_position: 15 },
    { key: "glutes", name: "Glutes", muscle_group: "hips", aliases: [ "Glutes" ], display_position: 16 },
    { key: "quadriceps", name: "Quadriceps", muscle_group: "legs", aliases: [ "Quads" ], display_position: 17 },
    { key: "hamstrings", name: "Hamstrings", muscle_group: "legs", aliases: [ "Hamstrings" ], display_position: 18 },
    { key: "calves", name: "Calves", muscle_group: "legs", aliases: [ "Calves" ], display_position: 19 }
  ].freeze

  KEYS = DEFAULT_MUSCLES.map { |row| row.fetch(:key) }.freeze
  MUSCLE_GROUPS = %w[chest shoulders arms back core hips legs].freeze

  def up
    create_table :muscles do |t|
      t.string :key, null: false
      t.string :name, null: false
      t.string :muscle_group, null: false
      t.json :aliases, null: false, default: []
      t.integer :display_position, null: false
      t.timestamps
      t.index :key, unique: true
      t.index :display_position, unique: true
      t.check_constraint "display_position > 0", name: "muscles_positive_display_position"
      t.check_constraint "muscle_group IN (#{quoted_list(MUSCLE_GROUPS)})", name: "muscles_muscle_group"
      t.check_constraint "key IN (#{quoted_list(KEYS)})", name: "muscles_key"
    end

    create_table :exercise_muscle_targets do |t|
      t.references :exercise, null: false, foreign_key: true
      t.references :muscle, null: false, foreign_key: true
      t.string :role, null: false
      t.timestamps
      t.index [ :exercise_id, :muscle_id ], unique: true
      t.check_constraint "role IN ('primary', 'secondary', 'stabilizer')", name: "exercise_muscle_targets_role"
    end

    now = connection.quote(Time.current)
    DEFAULT_MUSCLES.each do |row|
      execute <<~SQL.squish
        INSERT INTO muscles (key, name, muscle_group, aliases, display_position, created_at, updated_at)
        VALUES (
          #{connection.quote(row.fetch(:key))},
          #{connection.quote(row.fetch(:name))},
          #{connection.quote(row.fetch(:muscle_group))},
          #{connection.quote(row.fetch(:aliases).to_json)},
          #{row.fetch(:display_position)},
          #{now},
          #{now}
        )
      SQL
    end
  end

  def down
    drop_table :exercise_muscle_targets
    drop_table :muscles
  end

  private
    def quoted_list(values)
      values.map { |value| connection.quote(value) }.join(", ")
    end
end
