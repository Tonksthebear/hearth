class CreateRecipeIngredients < ActiveRecord::Migration[8.1]
  def change
    create_table :recipe_ingredients do |t|
      t.references :recipe, null: false, foreign_key: true
      t.text :amount
      t.string :unit
      t.string :name, null: false
      t.text :notes
      t.integer :position, null: false

      t.timestamps
    end

    add_index :recipe_ingredients, [ :recipe_id, :position ], unique: true
    add_check_constraint :recipe_ingredients, "position > 0", name: "recipe_ingredients_positive_position"
  end
end
