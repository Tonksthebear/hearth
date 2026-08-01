class CreateNutritionTrackingAndSnapshots < ActiveRecord::Migration[8.1]
  DEFAULT_NUTRIENTS = [
    [ "energy", "Energy", "kcal", "energy", 1 ],
    [ "protein", "Protein", "g", "macronutrient", 2 ],
    [ "carbohydrates", "Carbohydrates", "g", "macronutrient", 3 ],
    [ "fat", "Fat", "g", "macronutrient", 4 ],
    [ "fiber", "Fiber", "g", "macronutrient", 5 ],
    [ "sodium", "Sodium", "mg", "mineral", 6 ]
  ].freeze

  def up
    create_table :nutrients do |t|
      t.string :key, null: false
      t.string :name, null: false
      t.string :unit, null: false
      t.string :category, null: false
      t.integer :display_order, null: false
      t.timestamps
    end
    add_index :nutrients, :key, unique: true
    add_index :nutrients, :display_order, unique: true
    add_check_constraint :nutrients, "display_order > 0", name: "nutrients_positive_display_order"

    add_column :ingredients, :nutrition_source_name, :string
    add_column :ingredients, :nutrition_provenance_status, :string
    add_column :ingredients, :food_data_central_id, :string
    add_check_constraint :ingredients,
      "nutrition_provenance_status IS NULL OR nutrition_provenance_status IN ('personal', 'verified', 'adapted', 'observed')",
      name: "ingredients_nutrition_provenance_status"

    create_table :ingredient_nutrient_values do |t|
      t.references :ingredient, null: false, foreign_key: true
      t.references :nutrient, null: false, foreign_key: true
      t.decimal :amount_per_100_grams, precision: 14, scale: 6, null: false
      t.timestamps
    end
    add_index :ingredient_nutrient_values, [ :ingredient_id, :nutrient_id ], unique: true
    add_check_constraint :ingredient_nutrient_values, "amount_per_100_grams >= 0",
      name: "ingredient_nutrient_values_nonnegative_amount"

    add_column :recipes, :serving_count, :decimal, precision: 10, scale: 3
    add_check_constraint :recipes, "serving_count IS NULL OR serving_count > 0",
      name: "recipes_positive_serving_count"
    add_column :recipe_ingredients, :gram_weight, :decimal, precision: 10, scale: 3
    add_check_constraint :recipe_ingredients, "gram_weight IS NULL OR gram_weight > 0",
      name: "recipe_ingredients_positive_gram_weight"

    create_table :recipe_nutrient_values do |t|
      t.references :recipe, null: false, foreign_key: true
      t.references :nutrient, null: false, foreign_key: true
      t.decimal :amount, precision: 14, scale: 6, null: false
      t.timestamps
    end
    add_index :recipe_nutrient_values, [ :recipe_id, :nutrient_id ], unique: true
    add_check_constraint :recipe_nutrient_values, "amount >= 0",
      name: "recipe_nutrient_values_nonnegative_amount"

    add_column :meal_items, :nutrition_complete, :boolean, null: false, default: false
    add_column :meal_items, :nutrition_estimated, :boolean, null: false, default: false

    create_table :meal_item_nutrient_values do |t|
      t.references :meal_item, null: false, foreign_key: true
      t.references :nutrient, null: true, foreign_key: { on_delete: :nullify }
      t.decimal :amount, precision: 14, scale: 6, null: false
      t.string :snapshot_key, null: false
      t.string :snapshot_name, null: false
      t.string :snapshot_unit, null: false
      t.string :snapshot_source_name
      t.string :snapshot_provenance_status
      t.string :snapshot_calculation_kind, null: false
      t.timestamps
    end
    add_index :meal_item_nutrient_values, [ :meal_item_id, :snapshot_key ], unique: true,
      name: "index_meal_item_nutrients_on_item_and_snapshot_key"
    add_check_constraint :meal_item_nutrient_values, "amount >= 0",
      name: "meal_item_nutrient_values_nonnegative_amount"
    add_check_constraint :meal_item_nutrient_values,
      "snapshot_calculation_kind IN ('explicit', 'estimated')",
      name: "meal_item_nutrient_values_calculation_kind"

    now = connection.quote(Time.current)
    DEFAULT_NUTRIENTS.each do |key, name, unit, category, display_order|
      execute <<~SQL.squish
        INSERT INTO nutrients (key, name, unit, category, display_order, created_at, updated_at)
        VALUES (#{connection.quote(key)}, #{connection.quote(name)}, #{connection.quote(unit)},
          #{connection.quote(category)}, #{display_order}, #{now}, #{now})
      SQL
    end
  end

  def down
    drop_table :meal_item_nutrient_values
    remove_column :meal_items, :nutrition_estimated
    remove_column :meal_items, :nutrition_complete
    drop_table :recipe_nutrient_values
    remove_check_constraint :recipe_ingredients, name: "recipe_ingredients_positive_gram_weight"
    remove_column :recipe_ingredients, :gram_weight
    remove_check_constraint :recipes, name: "recipes_positive_serving_count"
    remove_column :recipes, :serving_count
    drop_table :ingredient_nutrient_values
    remove_check_constraint :ingredients, name: "ingredients_nutrition_provenance_status"
    remove_column :ingredients, :food_data_central_id
    remove_column :ingredients, :nutrition_provenance_status
    remove_column :ingredients, :nutrition_source_name
    drop_table :nutrients
  end
end
