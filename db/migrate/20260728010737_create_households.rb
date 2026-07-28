class CreateHouseholds < ActiveRecord::Migration[8.1]
  def change
    create_table :households do |t|
      t.string :name, null: false
      t.integer :installation_key, null: false, default: 1

      t.timestamps
    end

    add_check_constraint :households, "installation_key = 1", name: "households_single_installation"
    add_index :households, :installation_key, unique: true
  end
end
