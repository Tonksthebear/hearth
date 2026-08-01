require "test_helper"
require "tmpdir"
require Rails.root.join("db/migrate/20260731150000_replace_meal_logs_with_meals")

class ReplaceMealLogsWithMealsTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  PREVIOUS_VERSION = 20260731140000
  MIGRATION_VERSION = 20260731150000

  class IsolatedMigrationBase < ActiveRecord::Base
    self.abstract_class = true
  end

  test "legacy recipe and free text rows become one-item meal events without invented times" do
    with_isolated_database do |connection, context|
      context.migrate(PREVIOUS_VERSION)
      rows = seed_legacy_rows(connection)

      context.migrate

      assert_equal rows.keys.sort, connection.select_values("SELECT id FROM meals ORDER BY id").map(&:to_i)
      assert_equal 2, connection.select_value("SELECT COUNT(*) FROM meal_items")
      assert_equal [ "recipe", "free_text" ], connection.select_values("SELECT source_kind FROM meal_items ORDER BY meal_id")
      assert_equal [ "Migration recipe", "Travel sandwich" ], connection.select_values("SELECT snapshot_label FROM meal_items ORDER BY meal_id")
      assert_equal [ 1, 1 ], connection.select_values("SELECT position FROM meal_items ORDER BY meal_id").map(&:to_i)
      assert_equal [ nil, nil ], connection.select_values("SELECT eaten_at FROM meals ORDER BY id")
      refute connection.column_exists?(:meals, :recipe_id)
      refute connection.column_exists?(:meals, :ad_hoc_description)
      refute connection.table_exists?(:meal_logs)

      rows.each do |id, expected|
        actual = connection.select_one("SELECT household_id, person_id, eaten_on, created_at, updated_at FROM meals WHERE id = #{id}")
        assert_equal expected.stringify_keys, actual
      end
    end
  end

  test "fresh schema enforces item source position and feedback uniqueness" do
    with_isolated_database do |connection, context|
      context.migrate
      ids = seed_final_graph_parents(connection)
      item = insert(connection, :meal_items,
        meal_id: ids[:meal], recipe_id: ids[:recipe], source_kind: "recipe",
        snapshot_label: "Recipe snapshot", position: 1, created_at: Time.current, updated_at: Time.current)

      assert_raises(ActiveRecord::StatementInvalid) do
        insert(connection, :meal_items,
          meal_id: ids[:meal], source_kind: "free_text", snapshot_label: "Invalid", position: 0,
          created_at: Time.current, updated_at: Time.current)
      end
      assert_raises(ActiveRecord::StatementInvalid) do
        insert(connection, :meal_items,
          meal_id: ids[:meal], source_kind: "recipe", snapshot_label: "Missing recipe", position: 2,
          created_at: Time.current, updated_at: Time.current)
      end
      insert(connection, :meals,
        household_id: ids[:household], person_id: ids[:person], planned_meal_id: ids[:planned_meal],
        eaten_on: "2026-07-31", created_at: Time.current, updated_at: Time.current)
      assert_raises(ActiveRecord::RecordNotUnique) do
        insert(connection, :meals,
          household_id: ids[:household], person_id: ids[:person], planned_meal_id: ids[:planned_meal],
          eaten_on: "2026-07-31", created_at: Time.current, updated_at: Time.current)
      end
      insert(connection, :recipe_feedbacks, meal_item_id: item, body: "First", created_at: Time.current, updated_at: Time.current)
      assert_raises(ActiveRecord::RecordNotUnique) do
        insert(connection, :recipe_feedbacks, meal_item_id: item, body: "Second", created_at: Time.current, updated_at: Time.current)
      end
    end
  end

  test "down documents the backup restore boundary" do
    error = assert_raises(ActiveRecord::IrreversibleMigration) do
      ReplaceMealLogsWithMeals.new.migrate(:down)
    end

    assert_match(/restore a database backup/i, error.message)
  end

  private
    def with_isolated_database
      fixture_pool = ActiveRecord::Base.connection_pool
      result = Dir.mktmpdir([ "hearth-meals-migration-#{Process.pid}-", "" ]) do |directory|
        database = File.join(directory, "meals.sqlite3")
        original_verbosity = ActiveRecord::Migration.verbose
        database_tasks = ActiveRecord::Tasks::DatabaseTasks
        singleton = database_tasks.singleton_class
        original_method = :migration_class_before_meal_event_test
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
      now = Time.zone.local(2026, 7, 31, 10, 30)
      household = insert(connection, :households, name: "Migration home", installation_key: 1, created_at: now, updated_at: now)
      person = insert(connection, :people, household_id: household, name: "Migration person", created_at: now, updated_at: now)
      recipe = insert(connection, :recipes,
        household_id: household, title: "Migration recipe", provenance_status: "personal",
        created_at: now, updated_at: now)
      recipe_meal = insert(connection, :meal_logs,
        household_id: household, person_id: person, recipe_id: recipe, eaten_on: "2026-07-29",
        created_at: now, updated_at: now)
      free_text_meal = insert(connection, :meal_logs,
        household_id: household, person_id: person, ad_hoc_description: "Travel sandwich", eaten_on: "2026-07-30",
        created_at: now + 1.hour, updated_at: now + 2.hours)

      {
        recipe_meal => { household_id: household, person_id: person, eaten_on: "2026-07-29", created_at: now.utc.to_fs(:db), updated_at: now.utc.to_fs(:db) },
        free_text_meal => { household_id: household, person_id: person, eaten_on: "2026-07-30", created_at: (now + 1.hour).utc.to_fs(:db), updated_at: (now + 2.hours).utc.to_fs(:db) }
      }
    end

    def seed_final_graph_parents(connection)
      now = Time.current
      household = insert(connection, :households, name: "Final home", installation_key: 1, created_at: now, updated_at: now)
      person = insert(connection, :people, household_id: household, name: "Final person", created_at: now, updated_at: now)
      recipe = insert(connection, :recipes,
        household_id: household, title: "Final recipe", provenance_status: "personal",
        created_at: now, updated_at: now)
      planned_meal = insert(connection, :planned_meals,
        household_id: household, recipe_id: recipe, planned_on: "2026-07-31",
        created_at: now, updated_at: now)
      meal = insert(connection, :meals,
        household_id: household, person_id: person, eaten_on: "2026-07-31", created_at: now, updated_at: now)
      { household: household, person: person, recipe: recipe, planned_meal: planned_meal, meal: meal }
    end

    def insert(connection, table, attributes)
      columns = attributes.keys.map { |name| connection.quote_column_name(name) }.join(", ")
      values = attributes.values.map { |value| connection.quote(value) }.join(", ")
      connection.execute("INSERT INTO #{connection.quote_table_name(table)} (#{columns}) VALUES (#{values})")
      connection.select_value("SELECT last_insert_rowid()").to_i
    end
end
