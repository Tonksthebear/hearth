require "test_helper"
require "tmpdir"

# Adding the priority check constraint rebuilds planned_meals, and the rebuild
# drops the original table. planned_meal_ingredients and
# shopping_list_item_sources reference it ON DELETE CASCADE, so a rebuild that
# runs with foreign keys enforced silently deletes every requirement snapshot and
# shopping source in the database. bin/rails test loads db/schema.rb and never
# executes migrations, so only an isolated migration test can observe that.
class PlannedMealAllocationPriorityTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  PREVIOUS_VERSION = 20260805020000
  MIGRATION_VERSION = 20260805030000

  class IsolatedMigrationBase < ActiveRecord::Base
    self.abstract_class = true
  end

  test "the priority column arrives without deleting any row that depends on a plan" do
    with_isolated_database do |connection, context|
      context.migrate(PREVIOUS_VERSION)
      seeded = seed_planned_meal_rows(connection)

      context.migrate(MIGRATION_VERSION)

      assert_equal seeded.fetch(:plans), ids(connection, :planned_meals)
      assert_equal seeded.fetch(:requirements), ids(connection, :planned_meal_ingredients)
      assert_equal seeded.fetch(:sources), ids(connection, :shopping_list_item_sources)
      assert_equal seeded.fetch(:meals), ids(connection, :meals)
      assert_equal seeded.fetch(:plans),
        connection.select_values("SELECT planned_meal_id FROM planned_meal_ingredients ORDER BY planned_meal_id").map(&:to_i)
    end
  end

  test "existing plans start with no override and the database rejects a non-positive one" do
    with_isolated_database do |connection, context|
      context.migrate(PREVIOUS_VERSION)
      plans = seed_planned_meal_rows(connection).fetch(:plans)

      context.migrate(MIGRATION_VERSION)

      assert_equal [ nil, nil ], connection.select_values("SELECT allocation_priority FROM planned_meals")
      assert_raises(ActiveRecord::StatementInvalid) do
        connection.execute("UPDATE planned_meals SET allocation_priority = 0 WHERE id = #{plans.first}")
      end
      connection.execute("UPDATE planned_meals SET allocation_priority = 1 WHERE id = #{plans.first}")
      assert_equal [ 1 ], connection.select_values("SELECT allocation_priority FROM planned_meals WHERE id = #{plans.first}")
    end
  end

  private
    def with_isolated_database
      fixture_pool = ActiveRecord::Base.connection_pool
      result = Dir.mktmpdir([ "hearth-allocation-priority-migration-#{Process.pid}-", "" ]) do |directory|
        database = File.join(directory, "allocation_priority.sqlite3")
        original_verbosity = ActiveRecord::Migration.verbose
        database_tasks = ActiveRecord::Tasks::DatabaseTasks
        singleton = database_tasks.singleton_class
        original_method = :migration_class_before_allocation_priority_test
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

    def seed_planned_meal_rows(connection)
      now = Time.zone.local(2026, 8, 4, 9, 15)
      household = insert(connection, :households, name: "Allocation home", installation_key: 1, created_at: now, updated_at: now)
      person = insert(connection, :people, household_id: household, name: "Alex", created_at: now, updated_at: now)
      recipe = insert(connection, :recipes,
        household_id: household, title: "Weeknight chili", provenance_status: "personal", created_at: now, updated_at: now)
      ingredient = insert(connection, :ingredients,
        household_id: household, name: "Beans", normalized_name: "beans", created_at: now, updated_at: now)
      recipe_ingredient = insert(connection, :recipe_ingredients,
        recipe_id: recipe, ingredient_id: ingredient, display_name: "Beans", display_quantity: "2", unit: "can",
        quantity_numerator: 2, quantity_denominator: 1, position: 1, created_at: now, updated_at: now)
      shopping_list = insert(connection, :shopping_lists,
        household_id: household, week_start: "2026-08-10", created_at: now, updated_at: now)
      shopping_list_item = insert(connection, :shopping_list_items,
        shopping_list_id: shopping_list, name: "Beans", quantity: "2", unit: "can", created_at: now, updated_at: now)

      plans = [ "2026-08-10", "2026-08-11" ].map do |planned_on|
        insert(connection, :planned_meals,
          household_id: household, recipe_id: recipe, planned_on: planned_on,
          recipe_scale: 1.0, created_at: now, updated_at: now)
      end

      requirements = plans.map do |plan|
        insert(connection, :planned_meal_ingredients,
          planned_meal_id: plan, source_recipe_id: recipe, source_recipe_ingredient_id: recipe_ingredient,
          ingredient_id: ingredient, display_name: "Beans", display_quantity: "2", unit: "can",
          quantity_numerator: 2, quantity_denominator: 1, position: 1, decision: "unknown",
          created_at: now, updated_at: now)
      end
      sources = [
        insert(connection, :shopping_list_item_sources,
          planned_meal_id: plans.first, recipe_ingredient_id: recipe_ingredient,
          shopping_list_item_id: shopping_list_item, created_at: now, updated_at: now)
      ]
      meals = [
        insert(connection, :meals,
          household_id: household, person_id: person, planned_meal_id: plans.last,
          eaten_on: "2026-08-11", created_at: now, updated_at: now)
      ]

      { plans: plans.sort, requirements: requirements.sort, sources: sources.sort, meals: meals.sort }
    end

    def ids(connection, table)
      connection.select_values("SELECT id FROM #{table} ORDER BY id").map(&:to_i)
    end

    def insert(connection, table, attributes)
      columns = attributes.keys.map { |name| connection.quote_column_name(name) }.join(", ")
      values = attributes.values.map { |value| connection.quote(value) }.join(", ")
      connection.execute("INSERT INTO #{connection.quote_table_name(table)} (#{columns}) VALUES (#{values})")
      connection.select_value("SELECT last_insert_rowid()").to_i
    end
end
