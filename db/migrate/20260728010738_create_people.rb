class CreatePeople < ActiveRecord::Migration[8.1]
  def change
    create_table :people do |t|
      t.string :name, null: false
      t.references :household, null: false, foreign_key: true

      t.timestamps
    end
  end
end
