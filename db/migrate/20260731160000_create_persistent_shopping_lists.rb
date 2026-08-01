class CreatePersistentShoppingLists < ActiveRecord::Migration[8.1]
  def change
    create_table :shopping_lists do |t|
      t.references :household, null: false, foreign_key: { on_delete: :cascade }
      t.date :week_start, null: false
      t.timestamps
    end
    add_index :shopping_lists, [ :household_id, :week_start ], unique: true

    create_table :shopping_list_items do |t|
      t.references :shopping_list, null: false, foreign_key: { on_delete: :cascade }
      t.references :ingredient, foreign_key: true
      t.string :generated_key
      t.string :name, null: false
      t.string :quantity
      t.string :unit
      t.text :notes
      t.datetime :user_managed_at
      t.datetime :completed_at
      t.timestamps
    end
    add_index :shopping_list_items, [ :shopping_list_id, :generated_key ], unique: true,
      where: "generated_key IS NOT NULL",
      name: "index_shopping_items_on_list_and_generated_key"

    create_table :shopping_list_item_sources do |t|
      t.references :shopping_list_item, null: false, foreign_key: { on_delete: :cascade }
      t.references :planned_meal, null: false, foreign_key: { on_delete: :cascade }
      t.references :recipe_ingredient, null: false, foreign_key: { on_delete: :cascade }
      t.timestamps
    end
    add_index :shopping_list_item_sources, [ :planned_meal_id, :recipe_ingredient_id ],
      unique: true,
      name: "index_shopping_sources_on_plan_and_ingredient"
  end
end
