class NormalizeRecipeIngredientsAndEnrichRecipeInstructions < ActiveRecord::Migration[8.1]
  COLUMN_FINGERPRINTS = {
    ingredients: {
      id: { type: :integer, null: false },
      household_id: { type: :integer, null: false },
      name: { type: :string, null: false },
      normalized_name: { type: :string, null: false },
      created_at: { type: :datetime, null: false },
      updated_at: { type: :datetime, null: false }
    },
    recipe_ingredients: {
      display_name: { type: :string, null: false },
      display_quantity: { type: :text, null: true },
      ingredient_id: { type: :integer, null: false },
      quantity_numerator: { type: :integer, null: true },
      quantity_denominator: { type: :integer, null: true }
    },
    recipes: {
      import_key: { type: :string, null: true }
    },
    recipe_instructions: {
      duration_amount: { type: :decimal, null: true, precision: 10, scale: 2 },
      duration_unit: { type: :string, null: true },
      temperature_amount: { type: :decimal, null: true, precision: 10, scale: 2 },
      temperature_unit: { type: :string, null: true }
    },
    recipe_instruction_ingredients: {
      id: { type: :integer, null: false },
      recipe_id: { type: :integer, null: false },
      recipe_instruction_id: { type: :integer, null: false },
      recipe_ingredient_id: { type: :integer, null: false },
      position: { type: :integer, null: false },
      created_at: { type: :datetime, null: false },
      updated_at: { type: :datetime, null: false }
    }
  }.freeze

  INDEX_FINGERPRINTS = {
    ingredients: [
      [ %w[household_id], false, nil ],
      [ %w[household_id normalized_name], true, nil ]
    ],
    recipe_ingredients: [
      [ %w[ingredient_id], false, nil ],
      [ %w[id recipe_id], true, nil ]
    ],
    recipes: [
      [ %w[household_id import_key], true, "import_key IS NOT NULL" ]
    ],
    recipe_instructions: [
      [ %w[id recipe_id], true, nil ]
    ],
    recipe_instruction_ingredients: [
      [ %w[recipe_id], false, nil ],
      [ %w[recipe_instruction_id], false, nil ],
      [ %w[recipe_ingredient_id], false, nil ],
      [ %w[recipe_instruction_id recipe_ingredient_id], true, nil ],
      [ %w[recipe_instruction_id position], true, nil ]
    ]
  }.freeze

  CHECK_FINGERPRINTS = {
    recipe_ingredients: {
      "recipe_ingredients_quantity_pair" => "(quantity_numerator IS NULL AND quantity_denominator IS NULL) OR (quantity_numerator IS NOT NULL AND quantity_denominator IS NOT NULL)",
      "recipe_ingredients_positive_quantity_denominator" => "quantity_denominator IS NULL OR quantity_denominator > 0"
    },
    recipe_instructions: {
      "recipe_instructions_duration_pair" => "(duration_amount IS NULL AND duration_unit IS NULL) OR (duration_amount IS NOT NULL AND duration_unit IS NOT NULL)",
      "recipe_instructions_duration_unit" => "duration_unit IS NULL OR duration_unit IN ('seconds', 'minutes', 'hours')",
      "recipe_instructions_positive_duration" => "duration_amount IS NULL OR duration_amount > 0",
      "recipe_instructions_temperature_pair" => "(temperature_amount IS NULL AND temperature_unit IS NULL) OR (temperature_amount IS NOT NULL AND temperature_unit IS NOT NULL)",
      "recipe_instructions_temperature_unit" => "temperature_unit IS NULL OR temperature_unit IN ('F', 'C')"
    },
    recipe_instruction_ingredients: {
      "recipe_instruction_ingredients_positive_position" => "position > 0"
    }
  }.freeze

  FOREIGN_KEY_FINGERPRINTS = {
    ingredients: [ [ "households", %w[household_id], %w[id], nil, nil ] ],
    recipe_ingredients: [ [ "ingredients", %w[ingredient_id], %w[id], nil, nil ] ],
    recipe_instruction_ingredients: [
      [ "recipes", %w[recipe_id], %w[id], nil, nil ],
      [ "recipe_instructions", %w[recipe_instruction_id], %w[id], nil, nil ],
      [ "recipe_ingredients", %w[recipe_ingredient_id], %w[id], nil, nil ],
      [ "recipe_instructions", %w[recipe_instruction_id recipe_id], %w[id recipe_id], nil, nil ],
      [ "recipe_ingredients", %w[recipe_ingredient_id recipe_id], %w[id recipe_id], nil, nil ]
    ]
  }.freeze

  def up
    state = recipe_normalization_state
    return if state == :normalized

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
    def recipe_normalization_state
      normalized_differences = normalized_schema_differences
      return :normalized if normalized_differences.empty?

      legacy_differences = legacy_schema_differences
      return :legacy if legacy_differences.empty?

      raise <<~MESSAGE.squish
        Cannot normalize recipe ingredients from an unknown partial schema state.
        Missing or mismatched normalized effects: #{normalized_differences.join('; ')}.
        Legacy prerequisites or absence checks that failed: #{legacy_differences.join('; ')}.
      MESSAGE
    end

    def normalized_schema_differences
      differences = []

      COLUMN_FINGERPRINTS.each do |table, columns|
        unless connection.table_exists?(table)
          differences << "missing table #{table}"
          next
        end

        actual_columns = connection.columns(table).index_by { |column| column.name.to_sym }
        columns.each do |name, expected|
          column = actual_columns[name]
          if column.nil?
            differences << "missing column #{table}.#{name}"
          else
            expected.each do |attribute, value|
              actual = column.public_send(attribute)
              differences << "#{table}.#{name} #{attribute}=#{actual.inspect}, expected #{value.inspect}" unless actual == value
            end
          end
        end
      end

      if connection.table_exists?(:recipe_ingredients)
        differences << "legacy column recipe_ingredients.name is still present" if connection.column_exists?(:recipe_ingredients, :name)
        differences << "legacy column recipe_ingredients.amount is still present" if connection.column_exists?(:recipe_ingredients, :amount)
      end

      INDEX_FINGERPRINTS.each do |table, fingerprints|
        next unless connection.table_exists?(table)

        actual = connection.indexes(table).map do |index|
          [ Array(index.columns).map(&:to_s), index.unique, normalized_sql(index.where) ]
        end
        fingerprints.each do |fingerprint|
          expected = [ fingerprint[0], fingerprint[1], normalized_sql(fingerprint[2]) ]
          differences << "missing index on #{table} #{expected.inspect}" unless actual.include?(expected)
        end
      end

      CHECK_FINGERPRINTS.each do |table, fingerprints|
        next unless connection.table_exists?(table)

        actual = connection.check_constraints(table).to_h do |constraint|
          [ constraint.name, normalized_sql(constraint.expression) ]
        end
        fingerprints.each do |name, expression|
          expected = normalized_sql(expression)
          differences << "missing or mismatched check #{table}.#{name}" unless actual[name] == expected
        end
      end

      FOREIGN_KEY_FINGERPRINTS.each do |table, fingerprints|
        next unless connection.table_exists?(table)

        actual = connection.foreign_keys(table).map { |foreign_key| foreign_key_fingerprint(foreign_key) }
        fingerprints.each do |fingerprint|
          differences << "missing foreign key on #{table} #{fingerprint.inspect}" unless actual.include?(fingerprint)
        end
      end

      differences
    end

    def legacy_schema_differences
      differences = []
      prerequisites = {
        recipes: {},
        recipe_ingredients: {
          name: { type: :string, null: false },
          amount: { type: :text, null: true }
        },
        recipe_instructions: {}
      }

      prerequisites.each do |table, columns|
        unless connection.table_exists?(table)
          differences << "missing legacy table #{table}"
          next
        end

        actual_columns = connection.columns(table).index_by { |column| column.name.to_sym }
        columns.each do |name, expected|
          column = actual_columns[name]
          if column.nil?
            differences << "missing legacy column #{table}.#{name}"
          else
            expected.each do |attribute, value|
              actual = column.public_send(attribute)
              differences << "legacy #{table}.#{name} #{attribute}=#{actual.inspect}, expected #{value.inspect}" unless actual == value
            end
          end
        end
      end

      normalized_effects_present.each { |effect| differences << "normalized effect already present: #{effect}" }
      differences
    end

    def normalized_effects_present
      effects = []
      effects << "table ingredients" if connection.table_exists?(:ingredients)
      effects << "table recipe_instruction_ingredients" if connection.table_exists?(:recipe_instruction_ingredients)

      COLUMN_FINGERPRINTS.except(:ingredients, :recipe_instruction_ingredients).each do |table, columns|
        next unless connection.table_exists?(table)

        columns.each_key do |column|
          effects << "column #{table}.#{column}" if connection.column_exists?(table, column)
        end
      end

      if connection.table_exists?(:recipe_ingredients)
        effects << "renamed-away column recipe_ingredients.name" unless connection.column_exists?(:recipe_ingredients, :name)
        effects << "renamed-away column recipe_ingredients.amount" unless connection.column_exists?(:recipe_ingredients, :amount)
      end

      INDEX_FINGERPRINTS.each do |table, fingerprints|
        next unless connection.table_exists?(table)

        actual = connection.indexes(table).map do |index|
          [ Array(index.columns).map(&:to_s), index.unique, normalized_sql(index.where) ]
        end
        fingerprints.each do |fingerprint|
          expected = [ fingerprint[0], fingerprint[1], normalized_sql(fingerprint[2]) ]
          effects << "index on #{table} #{expected.inspect}" if actual.include?(expected)
        end
      end

      CHECK_FINGERPRINTS.each do |table, fingerprints|
        next unless connection.table_exists?(table)

        actual_names = connection.check_constraints(table).map(&:name)
        fingerprints.each_key do |name|
          effects << "check #{table}.#{name}" if actual_names.include?(name)
        end
      end

      FOREIGN_KEY_FINGERPRINTS.each do |table, fingerprints|
        next unless connection.table_exists?(table)

        actual = connection.foreign_keys(table).map { |foreign_key| foreign_key_fingerprint(foreign_key) }
        fingerprints.each do |fingerprint|
          effects << "foreign key on #{table} #{fingerprint.inspect}" if actual.include?(fingerprint)
        end
      end

      effects
    end

    def foreign_key_fingerprint(foreign_key)
      [
        foreign_key.to_table.to_s,
        Array(foreign_key.column).map(&:to_s),
        Array(foreign_key.primary_key || "id").map(&:to_s),
        foreign_key.options[:on_delete],
        foreign_key.options[:on_update]
      ]
    end

    def normalized_sql(sql)
      sql&.gsub(/\s+/, "")
    end

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
