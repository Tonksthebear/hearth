class AddPlannedMealAllocationPriority < ActiveRecord::Migration[8.1]
  # Adding a check constraint rebuilds planned_meals, and the rebuild drops the
  # original table. planned_meal_ingredients and shopping_list_item_sources
  # reference it ON DELETE CASCADE, so that drop deletes every requirement
  # snapshot and shopping source unless foreign keys are actually off. Rails
  # turns them off around the rebuild, but `PRAGMA foreign_keys` is a no-op
  # inside a transaction, so the surrounding DDL transaction has to go.
  disable_ddl_transaction!

  def change
    # Nullable with no default: NULL is the documented "no override" state, and
    # allocation sorts those last so existing plans keep date-plus-identity order.
    add_column :planned_meals, :allocation_priority, :integer

    add_index :planned_meals, [ :household_id, :allocation_priority ]

    add_check_constraint :planned_meals,
      "allocation_priority IS NULL OR allocation_priority > 0",
      name: "planned_meals_positive_allocation_priority"
  end
end
