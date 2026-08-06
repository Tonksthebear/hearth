class CreatePantryConsumptions < ActiveRecord::Migration[8.1]
  def change
    create_table :pantry_consumptions do |t|
      t.references :planned_meal, null: false, foreign_key: { on_delete: :cascade }
      # The requirement this draw answered is a point-in-time stamp, so the
      # reference is restricted rather than nullified: a requirement that drew
      # stock is superseded instead of destroyed.
      t.references :planned_meal_ingredient, null: false, foreign_key: { on_delete: :restrict }
      t.references :ingredient, null: false, foreign_key: true
      t.integer :quantity_numerator, null: false
      t.integer :quantity_denominator, null: false
      t.string :unit, null: false
      t.datetime :released_at
      t.string :released_reason

      t.timestamps
    end

    # Scoped to unreleased rows so a later cook/undo/cook cycle records a fresh
    # draw while released history accumulates behind it.
    add_index :pantry_consumptions, :planned_meal_ingredient_id,
      unique: true,
      where: "released_at IS NULL",
      name: "index_pantry_consumptions_on_active_requirement"

    add_check_constraint :pantry_consumptions, "quantity_numerator > 0",
      name: "pantry_consumptions_positive_quantity_numerator"
    add_check_constraint :pantry_consumptions, "quantity_denominator > 0",
      name: "pantry_consumptions_positive_quantity_denominator"
    add_check_constraint :pantry_consumptions, <<~SQL.squish, name: "pantry_consumptions_release_pair"
      (released_at IS NULL AND released_reason IS NULL) OR
      (released_at IS NOT NULL AND released_reason IS NOT NULL)
    SQL
    add_check_constraint :pantry_consumptions, <<~SQL.squish, name: "pantry_consumptions_released_reason"
      released_reason IS NULL OR released_reason IN
        ('credited', 'evidence_weakened', 'evidence_depleted', 'evidence_cleared', 'evidence_absent', 'unit_incompatible')
    SQL
  end
end
