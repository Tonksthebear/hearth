class CreatePantryItems < ActiveRecord::Migration[8.1]
  def change
    create_table :pantry_items do |t|
      t.references :household, null: false, foreign_key: true
      t.references :ingredient, null: false, foreign_key: true
      t.references :confirmed_by, null: false, foreign_key: { to_table: :people }
      t.string :state, null: false
      t.integer :quantity_numerator
      t.integer :quantity_denominator
      t.string :unit
      t.string :confirmation_source, null: false
      t.datetime :confirmed_at, null: false

      t.timestamps
    end

    add_index :pantry_items, [ :household_id, :ingredient_id ], unique: true

    add_check_constraint :pantry_items,
      "state IN ('confirmed', 'low', 'out', 'unknown')",
      name: "pantry_items_state"
    add_check_constraint :pantry_items,
      "(quantity_numerator IS NULL AND quantity_denominator IS NULL) OR (quantity_numerator IS NOT NULL AND quantity_denominator IS NOT NULL)",
      name: "pantry_items_quantity_pair"
    add_check_constraint :pantry_items,
      "quantity_denominator IS NULL OR quantity_denominator > 0",
      name: "pantry_items_positive_quantity_denominator"
    add_check_constraint :pantry_items,
      "state <> 'confirmed' OR (quantity_numerator IS NOT NULL AND quantity_numerator > 0 AND unit IS NOT NULL)",
      name: "pantry_items_confirmed_amount"
    add_check_constraint :pantry_items,
      "state = 'confirmed' OR (quantity_numerator IS NULL AND quantity_denominator IS NULL AND unit IS NULL)",
      name: "pantry_items_qualitative_amount"
  end
end
