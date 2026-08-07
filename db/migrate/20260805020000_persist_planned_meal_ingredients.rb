class PersistPlannedMealIngredients < ActiveRecord::Migration[8.1]
  def up
    add_column :planned_meals, :recipe_scale, :decimal, precision: 10, scale: 3, null: false, default: 1
    add_check_constraint :planned_meals, "recipe_scale > 0", name: "planned_meals_positive_recipe_scale"

    create_table :planned_meal_ingredients do |t|
      t.references :planned_meal, null: false, foreign_key: { on_delete: :cascade }
      t.references :source_recipe, foreign_key: { to_table: :recipes, on_delete: :nullify }
      t.references :source_recipe_ingredient, foreign_key: { to_table: :recipe_ingredients, on_delete: :nullify }
      t.references :ingredient, null: false, foreign_key: true
      t.string :display_name, null: false
      t.text :display_quantity
      t.string :unit
      t.integer :quantity_numerator
      t.integer :quantity_denominator
      t.integer :position, null: false
      t.string :decision, null: false, default: "unknown"
      t.datetime :decided_at
      t.references :replacement_ingredient, foreign_key: { to_table: :ingredients }
      t.string :replacement_display_name
      t.text :replacement_display_quantity
      t.string :replacement_unit
      t.integer :replacement_quantity_numerator
      t.integer :replacement_quantity_denominator
      t.string :replacement_decision
      t.datetime :superseded_at
      t.string :superseded_reason
      t.timestamps
    end
    add_index :planned_meal_ingredients, %i[ planned_meal_id source_recipe_ingredient_id ],
      unique: true,
      where: "superseded_at IS NULL",
      name: "index_planned_meal_ingredients_on_active_source"
    add_index :planned_meal_ingredients, %i[ planned_meal_id position ]

    add_check_constraint :planned_meal_ingredients, "position > 0",
      name: "planned_meal_ingredients_positive_position"
    add_check_constraint :planned_meal_ingredients,
      "decision IN ('unknown', 'on_hand', 'missing', 'substituted', 'not_needed')",
      name: "planned_meal_ingredients_decision"
    add_check_constraint :planned_meal_ingredients,
      "replacement_decision IS NULL OR replacement_decision IN ('unknown', 'on_hand', 'missing')",
      name: "planned_meal_ingredients_replacement_decision"
    add_check_constraint :planned_meal_ingredients, <<~SQL.squish, name: "planned_meal_ingredients_quantity_pair"
      (quantity_numerator IS NULL AND quantity_denominator IS NULL) OR
      (quantity_numerator IS NOT NULL AND quantity_denominator IS NOT NULL)
    SQL
    add_check_constraint :planned_meal_ingredients,
      "quantity_denominator IS NULL OR quantity_denominator > 0",
      name: "planned_meal_ingredients_positive_quantity_denominator"
    add_check_constraint :planned_meal_ingredients, <<~SQL.squish, name: "planned_meal_ingredients_replacement_quantity_pair"
      (replacement_quantity_numerator IS NULL AND replacement_quantity_denominator IS NULL) OR
      (replacement_quantity_numerator IS NOT NULL AND replacement_quantity_denominator IS NOT NULL)
    SQL
    add_check_constraint :planned_meal_ingredients,
      "replacement_quantity_denominator IS NULL OR replacement_quantity_denominator > 0",
      name: "planned_meal_ingredients_positive_replacement_quantity_denominator"
    add_check_constraint :planned_meal_ingredients, <<~SQL.squish, name: "planned_meal_ingredients_supersession_pair"
      (superseded_at IS NULL AND superseded_reason IS NULL) OR
      (superseded_at IS NOT NULL AND superseded_reason IS NOT NULL)
    SQL
    add_check_constraint :planned_meal_ingredients, <<~SQL.squish, name: "planned_meal_ingredients_active_source_present"
      superseded_at IS NOT NULL OR
      (source_recipe_id IS NOT NULL AND source_recipe_ingredient_id IS NOT NULL)
    SQL

    # Snapshot today's recipe requirements onto every existing plan at full yield
    # (recipe_scale 1), so no plan starts without its own decision surface. Raw SQL
    # keeps the backfill independent of runtime models, enums, and callbacks.
    now = quote(Time.current)
    execute <<~SQL.squish
      INSERT INTO planned_meal_ingredients
        (planned_meal_id, source_recipe_id, source_recipe_ingredient_id, ingredient_id,
         display_name, display_quantity, unit, quantity_numerator, quantity_denominator,
         position, decision, created_at, updated_at)
      SELECT planned_meals.id,
             recipe_ingredients.recipe_id,
             recipe_ingredients.id,
             recipe_ingredients.ingredient_id,
             recipe_ingredients.display_name,
             recipe_ingredients.display_quantity,
             recipe_ingredients.unit,
             recipe_ingredients.quantity_numerator,
             recipe_ingredients.quantity_denominator,
             recipe_ingredients.position,
             'unknown',
             #{now},
             #{now}
      FROM planned_meals
      JOIN recipe_ingredients ON recipe_ingredients.recipe_id = planned_meals.recipe_id
    SQL

    expected_count = select_value(<<~SQL.squish).to_i
      SELECT COUNT(*)
      FROM planned_meals
      JOIN recipe_ingredients ON recipe_ingredients.recipe_id = planned_meals.recipe_id
    SQL
    actual_count = select_value("SELECT COUNT(*) FROM planned_meal_ingredients").to_i
    unless expected_count == actual_count
      raise ActiveRecord::IrreversibleMigration,
        "Planned meal ingredient backfill produced #{actual_count} rows for #{expected_count} requirements."
    end
  end

  def down
    drop_table :planned_meal_ingredients
    remove_check_constraint :planned_meals, "recipe_scale > 0", name: "planned_meals_positive_recipe_scale"
    remove_column :planned_meals, :recipe_scale
  end
end
