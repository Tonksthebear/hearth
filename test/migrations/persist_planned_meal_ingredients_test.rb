require "test_helper"
require "tmpdir"

class PersistPlannedMealIngredientsTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  PREVIOUS_VERSION = 20260802020000
  MIGRATION_VERSION = 20260805020000

  class IsolatedMigrationBase < ActiveRecord::Base
    self.abstract_class = true
  end

  test "existing plans gain one full-yield unknown snapshot per line of their own recipe" do
    with_isolated_database do |connection, context|
      context.migrate(PREVIOUS_VERSION)
      seeded = seed_legacy_rows(connection)

      context.migrate

      assert_equal [ 1.0, 1.0, 1.0 ],
        connection.select_values("SELECT recipe_scale FROM planned_meals ORDER BY id").map(&:to_f)

      expected_pairs = seeded[:plans_on_shared_recipe].product(seeded[:shared_recipe_lines]).sort
      actual_pairs = connection.select_rows(<<~SQL.squish).map { |pair| pair.map(&:to_i) }.sort
        SELECT planned_meal_id, source_recipe_ingredient_id FROM planned_meal_ingredients
      SQL
      assert_equal expected_pairs, actual_pairs
      assert_equal expected_pairs.size, actual_pairs.uniq.size
      assert_equal 0, connection.select_value(<<~SQL.squish).to_i
        SELECT COUNT(*) FROM planned_meal_ingredients WHERE planned_meal_id = #{seeded[:plan_on_empty_recipe]}
      SQL

      assert_equal 0, connection.select_value(<<~SQL.squish).to_i
        SELECT COUNT(*) FROM planned_meal_ingredients
        WHERE decision != 'unknown'
           OR decided_at IS NOT NULL
           OR superseded_at IS NOT NULL
           OR superseded_reason IS NOT NULL
           OR replacement_ingredient_id IS NOT NULL
           OR replacement_display_name IS NOT NULL
           OR replacement_display_quantity IS NOT NULL
           OR replacement_unit IS NOT NULL
           OR replacement_quantity_numerator IS NOT NULL
           OR replacement_quantity_denominator IS NOT NULL
           OR replacement_decision IS NOT NULL
           OR created_at IS NULL
           OR updated_at IS NULL
      SQL

      assert_equal 0, connection.select_value(<<~SQL.squish).to_i
        SELECT COUNT(*) FROM planned_meal_ingredients
        JOIN planned_meals ON planned_meals.id = planned_meal_ingredients.planned_meal_id
        JOIN recipe_ingredients ON recipe_ingredients.id = planned_meal_ingredients.source_recipe_ingredient_id
        WHERE planned_meal_ingredients.source_recipe_id IS NULL
           OR planned_meal_ingredients.source_recipe_ingredient_id IS NULL
           OR planned_meal_ingredients.source_recipe_id != planned_meals.recipe_id
           OR planned_meal_ingredients.source_recipe_id != recipe_ingredients.recipe_id
           OR planned_meal_ingredients.ingredient_id != recipe_ingredients.ingredient_id
           OR planned_meal_ingredients.display_name != recipe_ingredients.display_name
           OR planned_meal_ingredients.position != recipe_ingredients.position
           OR planned_meal_ingredients.display_quantity IS NOT recipe_ingredients.display_quantity
           OR planned_meal_ingredients.unit IS NOT recipe_ingredients.unit
           OR planned_meal_ingredients.quantity_numerator IS NOT recipe_ingredients.quantity_numerator
           OR planned_meal_ingredients.quantity_denominator IS NOT recipe_ingredients.quantity_denominator
      SQL

      free_text = connection.select_one(<<~SQL.squish)
        SELECT display_quantity, unit, quantity_numerator, quantity_denominator
        FROM planned_meal_ingredients WHERE display_name = 'Salt' LIMIT 1
      SQL
      assert_equal({ "display_quantity" => "to taste", "unit" => nil, "quantity_numerator" => nil, "quantity_denominator" => nil }, free_text)
    end
  end

  private
    def with_isolated_database
      fixture_pool = ActiveRecord::Base.connection_pool
      result = Dir.mktmpdir([ "hearth-planned-meal-ingredients-migration-#{Process.pid}-", "" ]) do |directory|
        database = File.join(directory, "planned_meal_ingredients.sqlite3")
        original_verbosity = ActiveRecord::Migration.verbose
        database_tasks = ActiveRecord::Tasks::DatabaseTasks
        singleton = database_tasks.singleton_class
        original_method = :migration_class_before_planned_meal_ingredient_test
        redirected = false

        begin
          ActiveRecord::Migration.verbose = false
          IsolatedMigrationBase.establish_connection(adapter: "sqlite3", database: database)
          pool = IsolatedMigrationBase.connection_pool
          singleton.alias_method original_method, :migration_class
          singleton.define_method(:migration_class) { IsolatedMigrationBase }
          redirected = true
          context = ActiveRecord::MigrationContext.new(
            Rails.application.config.paths["db/migrate"].to_a,
            ActiveRecord::SchemaMigration.new(pool),
            ActiveRecord::InternalMetadata.new(pool)
          )
          pool.with_connection { |connection| yield connection, context }
        ensure
          if redirected
            singleton.alias_method :migration_class, original_method
            singleton.remove_method original_method
          end
          IsolatedMigrationBase.remove_connection
          ActiveRecord::Migration.verbose = original_verbosity
        end
      end
      assert_same fixture_pool, ActiveRecord::Base.connection_pool
      result
    end

    def seed_legacy_rows(connection)
      now = Time.zone.local(2026, 8, 4, 9, 15)
      # Hearth is a single-installation household, so the cross-contamination
      # control here is a second recipe rather than a second household.
      household = insert(connection, :households, name: "Migration home", installation_key: 1, created_at: now, updated_at: now)

      shared_recipe = insert(connection, :recipes,
        household_id: household, title: "Shared recipe", provenance_status: "personal",
        created_at: now, updated_at: now)
      empty_recipe = insert(connection, :recipes,
        household_id: household, title: "Recipe without lines", provenance_status: "personal",
        created_at: now, updated_at: now)

      lines = [
        [ "Rolled oats", "2", "cups", 2, 1, 1 ],
        [ "Butter", "1/2", "Tablespoons", 1, 2, 2 ],
        [ "Salt", "to taste", nil, nil, nil, 3 ]
      ].map do |display_name, display_quantity, unit, numerator, denominator, position|
        ingredient = insert(connection, :ingredients,
          household_id: household, name: display_name, normalized_name: display_name.downcase,
          created_at: now, updated_at: now)
        insert(connection, :recipe_ingredients,
          recipe_id: shared_recipe, ingredient_id: ingredient, display_name: display_name,
          display_quantity: display_quantity, unit: unit,
          quantity_numerator: numerator, quantity_denominator: denominator,
          position: position, created_at: now, updated_at: now)
      end

      plans_on_shared_recipe = [ "2026-08-10", "2026-08-11" ].map do |planned_on|
        insert(connection, :planned_meals,
          household_id: household, recipe_id: shared_recipe, planned_on: planned_on,
          created_at: now, updated_at: now)
      end
      plan_on_empty_recipe = insert(connection, :planned_meals,
        household_id: household, recipe_id: empty_recipe, planned_on: "2026-08-12",
        created_at: now, updated_at: now)

      {
        shared_recipe_lines: lines,
        plans_on_shared_recipe: plans_on_shared_recipe,
        plan_on_empty_recipe: plan_on_empty_recipe
      }
    end

    def insert(connection, table, attributes)
      columns = attributes.keys.map { |name| connection.quote_column_name(name) }.join(", ")
      values = attributes.values.map { |value| connection.quote(value) }.join(", ")
      connection.execute("INSERT INTO #{connection.quote_table_name(table)} (#{columns}) VALUES (#{values})")
      connection.select_value("SELECT last_insert_rowid()").to_i
    end
end
