class ReplaceShoppingProvenanceWithPlannedMealIngredients < ActiveRecord::Migration[8.1]
  # Shopping provenance now points at the plan's decision row instead of the
  # recipe line, and legacy rows carry no decision to point at. The cold switch
  # discards them outright: that is the contract's "surviving rows lose
  # planned-meal provenance", not a data-loss accident.
  #
  # shopping_list_item_sources is a leaf — nothing references it — so replacing
  # it cascades to nothing and needs no disabled DDL transaction the way the
  # planned_meals rebuild did.
  def up
    drop_table :shopping_list_item_sources

    create_table :shopping_list_item_sources do |t|
      t.references :shopping_list_item, null: false, foreign_key: { on_delete: :cascade }
      t.references :planned_meal_ingredient, null: false,
        foreign_key: { on_delete: :cascade },
        index: { unique: true }
      t.timestamps
    end
  end

  def down
    drop_table :shopping_list_item_sources

    create_table :shopping_list_item_sources do |t|
      t.references :planned_meal, null: false, foreign_key: { on_delete: :cascade }
      t.references :recipe_ingredient, null: false, foreign_key: { on_delete: :cascade }
      t.references :shopping_list_item, null: false, foreign_key: { on_delete: :cascade }
      t.timestamps
    end
    add_index :shopping_list_item_sources, %i[ planned_meal_id recipe_ingredient_id ],
      unique: true,
      name: "index_shopping_sources_on_plan_and_ingredient"
  end
end
