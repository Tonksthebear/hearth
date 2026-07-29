class CreateRecoveryHabits < ActiveRecord::Migration[8.1]
  def change
    create_table :habits do |t|
      t.references :household, null: false, foreign_key: true
      t.string :name, null: false
      t.text :description
      t.timestamps
    end
    add_index :habits, %i[ household_id name ], unique: true

    create_table :habit_metrics do |t|
      t.references :habit, null: false, foreign_key: true
      t.string :key, null: false
      t.string :label, null: false
      t.string :value_type, null: false
      t.string :unit
      t.integer :position, null: false
      t.timestamps
    end
    add_index :habit_metrics, %i[ habit_id key ], unique: true
    add_index :habit_metrics, %i[ habit_id position ], unique: true
    add_check_constraint :habit_metrics, "position > 0", name: "habit_metrics_positive_position"
    add_check_constraint :habit_metrics,
      "value_type IN ('number', 'duration', 'time_of_day', 'boolean')",
      name: "habit_metrics_value_type"

    create_table :person_habits do |t|
      t.references :person, null: false, foreign_key: true
      t.references :habit, null: false, foreign_key: true
      t.boolean :active, null: false, default: true
      t.integer :position, null: false
      t.boolean :monday, null: false, default: true
      t.boolean :tuesday, null: false, default: true
      t.boolean :wednesday, null: false, default: true
      t.boolean :thursday, null: false, default: true
      t.boolean :friday, null: false, default: true
      t.boolean :saturday, null: false, default: true
      t.boolean :sunday, null: false, default: true
      t.timestamps
    end
    add_index :person_habits, %i[ person_id habit_id ], unique: true
    add_index :person_habits, %i[ person_id position ]
    add_check_constraint :person_habits, "position > 0", name: "person_habits_positive_position"

    create_table :person_habit_metrics do |t|
      t.references :person_habit, null: false, foreign_key: true
      t.references :habit_metric, null: false, foreign_key: true
      t.decimal :number_value, precision: 12, scale: 3
      t.integer :duration_value
      t.time :time_of_day_value
      t.boolean :boolean_value
      t.timestamps
    end
    add_index :person_habit_metrics, %i[ person_habit_id habit_metric_id ],
      unique: true, name: "index_person_habit_metrics_on_configuration_and_metric"
    add_check_constraint :person_habit_metrics,
      "duration_value IS NULL OR duration_value >= 0",
      name: "person_habit_metrics_nonnegative_duration"
    add_check_constraint :person_habit_metrics, typed_value_count_sql("person_habit_metrics") + " <= 1",
      name: "person_habit_metrics_one_typed_value"

    create_table :habit_check_ins do |t|
      t.references :person_habit, null: false, foreign_key: true
      t.date :checked_on, null: false
      t.text :notes
      t.timestamps
    end
    add_index :habit_check_ins, %i[ person_habit_id checked_on ], unique: true

    create_table :habit_check_in_measurements do |t|
      t.references :habit_check_in, null: false, foreign_key: true
      t.references :habit_metric, null: false, foreign_key: true
      t.decimal :number_value, precision: 12, scale: 3
      t.integer :duration_value
      t.time :time_of_day_value
      t.boolean :boolean_value
      t.timestamps
    end
    add_index :habit_check_in_measurements, %i[ habit_check_in_id habit_metric_id ],
      unique: true, name: "index_habit_measurements_on_check_in_and_metric"
    add_check_constraint :habit_check_in_measurements,
      "duration_value IS NULL OR duration_value >= 0",
      name: "habit_measurements_nonnegative_duration"
    add_check_constraint :habit_check_in_measurements, typed_value_count_sql("habit_check_in_measurements") + " = 1",
      name: "habit_measurements_one_typed_value"
  end

  private
    def typed_value_count_sql(table)
      columns = %w[number_value duration_value time_of_day_value boolean_value]
      columns.map { |column| "(CASE WHEN #{table}.#{column} IS NULL THEN 0 ELSE 1 END)" }.join(" + ")
    end
end
