class CreateRecipes < ActiveRecord::Migration[8.1]
  def change
    create_table :recipes do |t|
      t.references :household, null: false, foreign_key: true
      t.string :title, null: false
      t.text :description
      t.string :yield
      t.string :source_name, null: false
      t.string :source_url
      t.string :provenance_status, null: false

      t.timestamps
    end

    add_index :recipes, [ :household_id, :provenance_status ]
    add_check_constraint :recipes,
      "provenance_status IN ('verified', 'adapted', 'observed')",
      name: "recipes_provenance_status"
  end
end
