require "test_helper"
require "tmpdir"

class ReplaceShoppingProvenanceWithPlannedMealIngredientsTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  PREVIOUS_VERSION = 20260805030000
  MIGRATION_VERSION = 20260805040000

  class IsolatedMigrationBase < ActiveRecord::Base
    self.abstract_class = true
  end

  test "legacy provenance is discarded while every shopping row and planned meal survives" do
    with_isolated_database do |connection, context|
      context.migrate(PREVIOUS_VERSION)
      seeded = seed_legacy_rows(connection)

      context.migrate

      assert_equal 0, connection.select_value("SELECT COUNT(*) FROM shopping_list_item_sources").to_i
      assert_equal seeded.fetch(:items).sort, ids(connection, :shopping_list_items)
      assert_equal seeded.fetch(:plans).sort, ids(connection, :planned_meals)
      assert_equal seeded.fetch(:requirements).sort, ids(connection, :planned_meal_ingredients)
      assert_equal 1, connection.select_value(<<~SQL.squish).to_i
        SELECT COUNT(*) FROM shopping_list_items WHERE user_managed_at IS NOT NULL
      SQL
      assert_equal 1, connection.select_value(<<~SQL.squish).to_i
        SELECT COUNT(*) FROM shopping_list_items WHERE completed_at IS NOT NULL
      SQL
    end
  end

  test "the rebuilt table keys provenance to one requirement and cascades from both parents" do
    with_isolated_database do |connection, context|
      context.migrate
      ids = seed_final_graph_parents(connection)

      refute connection.column_exists?(:shopping_list_item_sources, :recipe_ingredient_id)
      refute connection.column_exists?(:shopping_list_item_sources, :planned_meal_id)
      assert connection.columns(:shopping_list_item_sources)
        .find { |column| column.name == "planned_meal_ingredient_id" }.null == false

      source = insert(connection, :shopping_list_item_sources,
        shopping_list_item_id: ids[:item], planned_meal_ingredient_id: ids[:requirement],
        created_at: Time.current, updated_at: Time.current)

      assert_raises(ActiveRecord::RecordNotUnique) do
        insert(connection, :shopping_list_item_sources,
          shopping_list_item_id: ids[:other_item], planned_meal_ingredient_id: ids[:requirement],
          created_at: Time.current, updated_at: Time.current)
      end
      assert_raises(ActiveRecord::InvalidForeignKey) do
        insert(connection, :shopping_list_item_sources,
          shopping_list_item_id: ids[:item], planned_meal_ingredient_id: 0,
          created_at: Time.current, updated_at: Time.current)
      end

      connection.execute("DELETE FROM planned_meal_ingredients WHERE id = #{ids[:requirement]}")
      assert_nil connection.select_value("SELECT id FROM shopping_list_item_sources WHERE id = #{source}")
    end
  end

  private
    def with_isolated_database
      fixture_pool = ActiveRecord::Base.connection_pool
      result = Dir.mktmpdir([ "hearth-shopping-provenance-#{Process.pid}-", "" ]) do |directory|
        database = File.join(directory, "shopping.sqlite3")
        original_verbosity = ActiveRecord::Migration.verbose
        database_tasks = ActiveRecord::Tasks::DatabaseTasks
        singleton = database_tasks.singleton_class
        original_method = :migration_class_before_shopping_provenance_test
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

    def ids(connection, table)
      connection.select_values("SELECT id FROM #{table} ORDER BY id").map(&:to_i)
    end

    def seed_legacy_rows(connection)
      now = Time.zone.local(2026, 8, 5, 10)
      graph = seed_shopping_graph(connection, now)

      untouched = insert(connection, :shopping_list_items,
        shopping_list_id: graph[:list], name: "Untouched carrots", quantity: "2", unit: "cup",
        generated_key: [ "ingredient", graph[:ingredient], "cup" ].to_json, created_at: now, updated_at: now)
      edited = insert(connection, :shopping_list_items,
        shopping_list_id: graph[:list], name: "Farm carrots", quantity: "4", unit: "cup",
        generated_key: [ "ingredient", graph[:ingredient], "can" ].to_json,
        user_managed_at: now, created_at: now, updated_at: now)
      completed = insert(connection, :shopping_list_items,
        shopping_list_id: graph[:list], name: "Aluminum foil", quantity: "1", unit: "roll",
        generated_key: [ "source", graph[:plan], graph[:recipe_ingredient] ].to_json,
        completed_at: now, created_at: now, updated_at: now)
      manual = insert(connection, :shopping_list_items,
        shopping_list_id: graph[:list], name: "Party napkins", created_at: now, updated_at: now)

      [ untouched, edited, completed ].each_with_index do |item, index|
        insert(connection, :shopping_list_item_sources,
          shopping_list_item_id: item, planned_meal_id: graph[:plan],
          recipe_ingredient_id: index.zero? ? graph[:recipe_ingredient] : graph[:"extra_recipe_ingredient_#{index}"],
          created_at: now, updated_at: now)
      end

      {
        items: [ untouched, edited, completed, manual ],
        plans: [ graph[:plan] ],
        requirements: [ graph[:requirement] ]
      }
    end

    def seed_shopping_graph(connection, now)
      household = insert(connection, :households, name: "Provenance home", installation_key: 1, created_at: now, updated_at: now)
      ingredient = insert(connection, :ingredients,
        household_id: household, name: "Carrots", normalized_name: "carrots", created_at: now, updated_at: now)
      recipe = insert(connection, :recipes,
        household_id: household, title: "Soup", source_name: "Test", provenance_status: "observed",
        created_at: now, updated_at: now)
      recipe_ingredients = (1..3).map do |position|
        insert(connection, :recipe_ingredients,
          recipe_id: recipe, ingredient_id: ingredient, display_name: "Carrots", display_quantity: "2",
          unit: "cup", quantity_numerator: 2, quantity_denominator: 1, position: position,
          created_at: now, updated_at: now)
      end
      plan = insert(connection, :planned_meals,
        household_id: household, recipe_id: recipe, planned_on: "2026-08-05", recipe_scale: 1,
        created_at: now, updated_at: now)
      requirement = insert(connection, :planned_meal_ingredients,
        planned_meal_id: plan, source_recipe_id: recipe, source_recipe_ingredient_id: recipe_ingredients.first,
        ingredient_id: ingredient, display_name: "Carrots", display_quantity: "2", unit: "cup",
        quantity_numerator: 2, quantity_denominator: 1, position: 1, decision: "missing",
        decided_at: now, created_at: now, updated_at: now)
      list = insert(connection, :shopping_lists,
        household_id: household, week_start: "2026-08-03", created_at: now, updated_at: now)

      {
        household: household, ingredient: ingredient, recipe: recipe, plan: plan, requirement: requirement,
        list: list, recipe_ingredient: recipe_ingredients.first,
        extra_recipe_ingredient_1: recipe_ingredients.second, extra_recipe_ingredient_2: recipe_ingredients.third
      }
    end

    def seed_final_graph_parents(connection)
      now = Time.current
      graph = seed_shopping_graph(connection, now)
      item = insert(connection, :shopping_list_items,
        shopping_list_id: graph[:list], name: "Carrots", quantity: "2", unit: "cup",
        generated_key: [ "deficit", graph[:ingredient], "cup" ].to_json, created_at: now, updated_at: now)
      other_item = insert(connection, :shopping_list_items,
        shopping_list_id: graph[:list], name: "Other", created_at: now, updated_at: now)

      graph.merge(item: item, other_item: other_item)
    end

    def insert(connection, table, attributes)
      columns = attributes.keys.map { |name| connection.quote_column_name(name) }.join(", ")
      values = attributes.values.map { |value| connection.quote(value) }.join(", ")
      connection.execute("INSERT INTO #{connection.quote_table_name(table)} (#{columns}) VALUES (#{values})")
      connection.select_value("SELECT last_insert_rowid()").to_i
    end
end
