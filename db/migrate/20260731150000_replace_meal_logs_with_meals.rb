class ReplaceMealLogsWithMeals < ActiveRecord::Migration[8.1]
  def up
    rename_table :meal_logs, :meals

    change_table :meals, bulk: true do |t|
      t.datetime :eaten_at
      t.text :notes
      t.references :planned_meal, foreign_key: true
    end
    add_index :meals, [ :planned_meal_id, :person_id ], unique: true,
      where: "planned_meal_id IS NOT NULL",
      name: "index_meals_on_planned_meal_and_person"

    create_table :legacy_meal_item_backfill, id: false do |t|
      t.integer :meal_id, null: false
      t.integer :recipe_id
      t.string :source_kind, null: false
      t.string :snapshot_label, null: false
      t.datetime :created_at, null: false
      t.datetime :updated_at, null: false
    end
    execute <<~SQL.squish
      INSERT INTO legacy_meal_item_backfill
        (meal_id, recipe_id, source_kind, snapshot_label, created_at, updated_at)
      SELECT meals.id,
             meals.recipe_id,
             CASE WHEN meals.recipe_id IS NULL THEN 'free_text' ELSE 'recipe' END,
             CASE WHEN meals.recipe_id IS NULL THEN meals.ad_hoc_description ELSE recipes.title END,
             meals.created_at,
             meals.updated_at
      FROM meals
      LEFT JOIN recipes ON recipes.id = meals.recipe_id
    SQL

    legacy_count = select_value("SELECT COUNT(*) FROM meals").to_i
    backfill_count = select_value("SELECT COUNT(*) FROM legacy_meal_item_backfill").to_i
    invalid_backfill_count = select_value(<<~SQL.squish).to_i
      SELECT COUNT(*) FROM legacy_meal_item_backfill
      WHERE snapshot_label IS NULL OR snapshot_label = ''
    SQL
    unless legacy_count == backfill_count && invalid_backfill_count.zero?
      raise ActiveRecord::IrreversibleMigration,
        "Meal backfill staging failed validation (#{legacy_count} meals, #{backfill_count} items, #{invalid_backfill_count} invalid)."
    end

    remove_reference :meals, :recipe, foreign_key: true
    remove_column :meals, :ad_hoc_description, :text

    create_table :meal_items do |t|
      t.references :meal, null: false, foreign_key: { on_delete: :cascade }
      t.references :recipe, foreign_key: true
      t.references :ingredient, foreign_key: true
      t.string :source_kind, null: false
      t.string :snapshot_label, null: false
      t.decimal :portion_amount, precision: 10, scale: 3
      t.string :portion_unit
      t.text :substitutions
      t.text :notes
      t.integer :position, null: false
      t.timestamps
    end
    add_index :meal_items, [ :meal_id, :position ], unique: true
    add_check_constraint :meal_items, "position > 0", name: "meal_items_positive_position"
    add_check_constraint :meal_items, "portion_amount IS NULL OR portion_amount > 0",
      name: "meal_items_positive_portion_amount"
    add_check_constraint :meal_items, <<~SQL.squish, name: "meal_items_exactly_one_source"
      (source_kind = 'recipe' AND recipe_id IS NOT NULL AND ingredient_id IS NULL) OR
      (source_kind = 'ingredient' AND recipe_id IS NULL AND ingredient_id IS NOT NULL) OR
      (source_kind = 'free_text' AND recipe_id IS NULL AND ingredient_id IS NULL)
    SQL

    create_table :recipe_feedbacks do |t|
      t.references :meal_item, null: false, foreign_key: { on_delete: :cascade }, index: { unique: true }
      t.text :body, null: false
      t.timestamps
    end

    execute <<~SQL.squish
      INSERT INTO meal_items
        (meal_id, recipe_id, source_kind, snapshot_label, position, created_at, updated_at)
      SELECT meal_id,
             recipe_id,
             source_kind,
             snapshot_label,
             1,
             created_at,
             updated_at
      FROM legacy_meal_item_backfill
    SQL

    item_count = select_value("SELECT COUNT(*) FROM meal_items").to_i
    invalid_count = select_value(<<~SQL.squish).to_i
      SELECT COUNT(*)
      FROM meals
      LEFT JOIN meal_items ON meal_items.meal_id = meals.id AND meal_items.position = 1
      WHERE meal_items.id IS NULL OR meal_items.snapshot_label IS NULL OR meal_items.snapshot_label = ''
    SQL
    unless legacy_count == item_count && invalid_count.zero?
      raise ActiveRecord::IrreversibleMigration,
        "Meal backfill failed validation (#{legacy_count} meals, #{item_count} items, #{invalid_count} invalid)."
    end
    drop_table :legacy_meal_item_backfill
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
      "Complete meal events cannot be reduced to one recipe-or-description row. Restore a database backup instead."
  end
end
