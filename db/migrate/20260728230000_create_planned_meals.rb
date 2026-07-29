class CreatePlannedMeals < ActiveRecord::Migration[8.1]
  def change
    create_table :planned_meals do |t|
      t.references :household, null: false, foreign_key: true
      t.references :person, null: true, foreign_key: true
      t.references :recipe, null: false, foreign_key: true
      t.date :planned_on, null: false

      t.timestamps
    end

    add_index :planned_meals, [ :household_id, :planned_on ]
    add_index :planned_meals, [ :person_id, :planned_on ]
  end
end
