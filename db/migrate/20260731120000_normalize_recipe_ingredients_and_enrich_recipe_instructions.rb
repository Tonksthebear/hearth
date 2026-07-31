class NormalizeRecipeIngredientsAndEnrichRecipeInstructions < ActiveRecord::Migration[8.1]
  def up
    create_table :ingredients do |t|
      t.references :household, null: false, foreign_key: true
      t.string :name, null: false
      t.string :normalized_name, null: false
      t.timestamps
    end
    add_index :ingredients, [ :household_id, :normalized_name ], unique: true

    rename_column :recipe_ingredients, :name, :display_name
    rename_column :recipe_ingredients, :amount, :display_quantity
    add_reference :recipe_ingredients, :ingredient, foreign_key: true
    add_column :recipe_ingredients, :quantity_numerator, :integer
    add_column :recipe_ingredients, :quantity_denominator, :integer

    backfill_ingredients_and_quantities

    change_column_null :recipe_ingredients, :ingredient_id, false
    add_check_constraint :recipe_ingredients,
      "(quantity_numerator IS NULL AND quantity_denominator IS NULL) OR (quantity_numerator IS NOT NULL AND quantity_denominator IS NOT NULL)",
      name: "recipe_ingredients_quantity_pair"
    add_check_constraint :recipe_ingredients,
      "quantity_denominator IS NULL OR quantity_denominator > 0",
      name: "recipe_ingredients_positive_quantity_denominator"

    add_column :recipes, :import_key, :string
    add_index :recipes, [ :household_id, :import_key ],
      unique: true,
      where: "import_key IS NOT NULL",
      name: "index_recipes_on_household_and_import_key"

    add_column :recipe_instructions, :duration_amount, :decimal, precision: 10, scale: 2
    add_column :recipe_instructions, :duration_unit, :string
    add_column :recipe_instructions, :temperature_amount, :decimal, precision: 10, scale: 2
    add_column :recipe_instructions, :temperature_unit, :string
    add_check_constraint :recipe_instructions,
      "(duration_amount IS NULL AND duration_unit IS NULL) OR (duration_amount IS NOT NULL AND duration_unit IS NOT NULL)",
      name: "recipe_instructions_duration_pair"
    add_check_constraint :recipe_instructions,
      "duration_unit IS NULL OR duration_unit IN ('seconds', 'minutes', 'hours')",
      name: "recipe_instructions_duration_unit"
    add_check_constraint :recipe_instructions,
      "duration_amount IS NULL OR duration_amount > 0",
      name: "recipe_instructions_positive_duration"
    add_check_constraint :recipe_instructions,
      "(temperature_amount IS NULL AND temperature_unit IS NULL) OR (temperature_amount IS NOT NULL AND temperature_unit IS NOT NULL)",
      name: "recipe_instructions_temperature_pair"
    add_check_constraint :recipe_instructions,
      "temperature_unit IS NULL OR temperature_unit IN ('F', 'C')",
      name: "recipe_instructions_temperature_unit"

    add_index :recipe_instructions, [ :id, :recipe_id ], unique: true
    add_index :recipe_ingredients, [ :id, :recipe_id ], unique: true

    create_table :recipe_instruction_ingredients do |t|
      t.references :recipe, null: false, foreign_key: true
      t.references :recipe_instruction, null: false, foreign_key: true
      t.references :recipe_ingredient, null: false, foreign_key: true
      t.integer :position, null: false
      t.timestamps
    end
    add_index :recipe_instruction_ingredients,
      [ :recipe_instruction_id, :recipe_ingredient_id ],
      unique: true,
      name: "index_instruction_ingredients_on_instruction_and_ingredient"
    add_index :recipe_instruction_ingredients,
      [ :recipe_instruction_id, :position ],
      unique: true,
      name: "index_instruction_ingredients_on_instruction_and_position"
    add_check_constraint :recipe_instruction_ingredients,
      "position > 0",
      name: "recipe_instruction_ingredients_positive_position"
    add_foreign_key :recipe_instruction_ingredients, :recipe_instructions,
      column: [ :recipe_instruction_id, :recipe_id ],
      primary_key: [ :id, :recipe_id ],
      name: "fk_instruction_ingredients_same_recipe_instruction"
    add_foreign_key :recipe_instruction_ingredients, :recipe_ingredients,
      column: [ :recipe_ingredient_id, :recipe_id ],
      primary_key: [ :id, :recipe_id ],
      name: "fk_instruction_ingredients_same_recipe_ingredient"
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
      "Canonical ingredient merges cannot be reversed without inventing discarded identity boundaries."
  end

  private
    def backfill_ingredients_and_quantities
      rows = select_all(<<~SQL)
        SELECT recipe_ingredients.id,
               recipe_ingredients.display_name,
               recipe_ingredients.display_quantity,
               recipes.household_id
          FROM recipe_ingredients
          JOIN recipes ON recipes.id = recipe_ingredients.recipe_id
         ORDER BY recipe_ingredients.id
      SQL

      rows.each do |row|
        ingredient_id = ingredient_id_for(row.fetch("household_id"), row.fetch("display_name"))
        numerator, denominator = quantity_parts(row["display_quantity"])

        execute <<~SQL
          UPDATE recipe_ingredients
             SET ingredient_id = #{quote_value(ingredient_id)},
                 quantity_numerator = #{quote_value(numerator)},
                 quantity_denominator = #{quote_value(denominator)}
           WHERE id = #{quote_value(row.fetch("id"))}
        SQL
      end
    end

    def ingredient_id_for(household_id, display_name)
      normalized_name = display_name.to_s.squish.downcase(:fold)
      existing_id = select_value(<<~SQL)
        SELECT id
          FROM ingredients
         WHERE household_id = #{quote_value(household_id)}
           AND normalized_name = #{quote_value(normalized_name)}
      SQL
      return existing_id if existing_id

      timestamp = quote_value(Time.current)
      execute <<~SQL
        INSERT INTO ingredients (household_id, name, normalized_name, created_at, updated_at)
        VALUES (#{quote_value(household_id)}, #{quote_value(display_name.to_s.squish)}, #{quote_value(normalized_name)}, #{timestamp}, #{timestamp})
      SQL
      select_value("SELECT id FROM ingredients WHERE household_id = #{quote_value(household_id)} AND normalized_name = #{quote_value(normalized_name)}")
    end

    def quantity_parts(display_quantity)
      value = display_quantity.to_s.strip
      return [ nil, nil ] if value.blank?

      quantity = if (match = value.match(/\A(\d+)\s+(\d+)\/(\d+)\z/))
        Rational(match[1].to_i, 1) + Rational(match[2].to_i, match[3].to_i)
      elsif value.match?(/\A\d+(?:\.\d+)?\z/)
        value.to_r
      elsif (match = value.match(/\A(\d+)\/(\d+)\z/))
        Rational(match[1].to_i, match[2].to_i)
      end

      quantity ? [ quantity.numerator, quantity.denominator ] : [ nil, nil ]
    rescue ZeroDivisionError
      [ nil, nil ]
    end

    def quote_value(value)
      connection.quote(value)
    end
end
