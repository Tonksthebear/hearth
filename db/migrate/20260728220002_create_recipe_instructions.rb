class CreateRecipeInstructions < ActiveRecord::Migration[8.1]
  def change
    create_table :recipe_instructions do |t|
      t.references :recipe, null: false, foreign_key: true
      t.text :body, null: false
      t.integer :position, null: false

      t.timestamps
    end

    add_index :recipe_instructions, [ :recipe_id, :position ], unique: true
    add_check_constraint :recipe_instructions, "position > 0", name: "recipe_instructions_positive_position"
  end
end
