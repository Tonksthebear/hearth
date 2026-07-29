class CreateMealLogs < ActiveRecord::Migration[8.1]
  def change
    create_table :meal_logs do |t|
      t.references :household, null: false, foreign_key: true
      t.references :person, null: false, foreign_key: true
      t.references :recipe, null: true, foreign_key: true
      t.text :ad_hoc_description
      t.date :eaten_on, null: false

      t.timestamps
    end

    add_index :meal_logs, [ :household_id, :eaten_on ]
    add_index :meal_logs, [ :person_id, :eaten_on ]
  end
end
