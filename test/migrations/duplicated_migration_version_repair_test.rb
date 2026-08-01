require "test_helper"
require "fileutils"
require "stringio"
require "tmpdir"
require Rails.root.join("db/migrate/20260731130000_normalize_recipe_ingredients_and_enrich_recipe_instructions")
require Rails.root.join("db/migrate/20260731140000_reconcile_runtime_agent_session_and_grant_nullability")

class DuplicatedMigrationVersionRepairTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  PRE_COLLISION_VERSION = 20260731043719
  RUNTIME_VERSION = 20260731120000
  WORKOUT_VERSION = 20260731120001
  RECIPE_VERSION = 20260731130000
  RECONCILIATION_VERSION = 20260731140000
  MEAL_EVENTS_VERSION = 20260731150000
  SHOPPING_VERSION = 20260731160000
  NUTRITION_VERSION = 20260731170000

  class IsolatedMigrationBase < ActiveRecord::Base
    self.abstract_class = true
  end

  class SentinelMigration < ActiveRecord::Migration[8.1]
    def up
      create_table :duplicated_version_repair_route_sentinels
    end
  end

  test "migration versions have one owner" do
    versions = Dir[Rails.root.join("db/migrate/*.rb")].map { |path| File.basename(path, ".rb").split("_", 2).first }
    duplicates = versions.tally.select { |_version, count| count > 1 }

    assert_empty duplicates, "migration versions must have exactly one owner, found duplicates: #{duplicates.inspect}"

    [ RUNTIME_VERSION, WORKOUT_VERSION, RECIPE_VERSION, RECONCILIATION_VERSION, MEAL_EVENTS_VERSION, SHOPPING_VERSION, NUTRITION_VERSION ].each do |version|
      assert_equal 1, versions.count(version.to_s), "expected migration version #{version} to have exactly one owner"
    end
  end

  test "isolated harness routes actual migration DDL away from the fixture database" do
    fixture_connection = ActiveRecord::Base.connection
    refute fixture_connection.data_source_exists?(:duplicated_version_repair_route_sentinels)

    with_isolated_database do |connection, _context, _pool|
      SentinelMigration.new.migrate(:up)

      assert connection.data_source_exists?(:duplicated_version_repair_route_sentinels)
      refute fixture_connection.data_source_exists?(:duplicated_version_repair_route_sentinels)
    end
  end

  test "isolated harness removes its registered pool after success and exceptions" do
    with_isolated_database { }
    assert_nil IsolatedMigrationBase.connection_handler.retrieve_connection_pool(IsolatedMigrationBase.name)

    error = assert_raises(RuntimeError) do
      with_isolated_database { raise "expected isolated harness failure" }
    end

    assert_equal "expected isolated harness failure", error.message
    assert_nil IsolatedMigrationBase.connection_handler.retrieve_connection_pool(IsolatedMigrationBase.name)
  end

  test "fresh and collided histories converge without losing data" do
    canonical_schema = with_isolated_database do |connection, context, pool|
      context.migrate

      assert_supported_final_state(connection)
      assert_equal [ RUNTIME_VERSION, WORKOUT_VERSION, RECIPE_VERSION, RECONCILIATION_VERSION, MEAL_EVENTS_VERSION, SHOPPING_VERSION, NUTRITION_VERSION ],
        context.get_all_versions.select { |version| version >= RUNTIME_VERSION }
      schema_dump(pool)
    end

    runtime_only_schema = with_isolated_database do |connection, context, pool|
      context.migrate(RUNTIME_VERSION)
      recipe_rows = seed_legacy_recipe_rows(connection)

      context.migrate

      assert_recipe_backfill(connection, recipe_rows)
      assert_supported_final_state(connection)
      schema_dump(pool)
    end
    assert_equal canonical_schema, runtime_only_schema

    recipe_only_schema = with_isolated_database do |connection, context, pool|
      context.migrate(PRE_COLLISION_VERSION)
      recipe_migration(context).migrate(:up)
      record_migration_version(connection, RUNTIME_VERSION)
      agent_rows = seed_agent_rows(connection)

      context.migrate

      assert_agent_rows_survived(connection, agent_rows)
      assert_agent_session_rebuild_fidelity(connection)
      assert_supported_final_state(connection)
      schema_dump(pool)
    end
    assert_equal canonical_schema, recipe_only_schema

    both_effects_schema = with_isolated_database do |connection, context, pool|
      context.migrate
      connection.execute("DELETE FROM schema_migrations WHERE version IN ('#{RECIPE_VERSION}', '#{RECONCILIATION_VERSION}')")

      context.migrate

      assert_supported_final_state(connection)
      schema_dump(pool)
    end
    assert_equal canonical_schema, both_effects_schema
  end

  test "partial normalized ingredient schema fails before DDL" do
    with_isolated_database do |connection, context, _pool|
      context.migrate(PRE_COLLISION_VERSION)
      recipe_migration(context).migrate(:up)
      record_migration_version(connection, RUNTIME_VERSION)
      connection.remove_foreign_key :recipe_instruction_ingredients,
        :recipe_ingredients,
        column: [ :recipe_ingredient_id, :recipe_id ]

      error = assert_raises(StandardError) { context.migrate(RECIPE_VERSION) }

      assert_match(/unknown partial schema state/i, error.message)
      assert_match(/recipe_ingredient_id.*recipe_id/i, error.message)
      refute_includes context.get_all_versions, RECIPE_VERSION
    end
  end

  test "semantically identical check constraint formatting is accepted" do
    with_isolated_database do |connection, context, _pool|
      context.migrate(PRE_COLLISION_VERSION)
      recipe_migration(context).migrate(:up)
      connection.remove_check_constraint :recipe_instructions,
        name: "recipe_instructions_positive_duration"
      connection.add_check_constraint :recipe_instructions,
        "duration_amount   IS NULL OR\n duration_amount > 0",
        name: "recipe_instructions_positive_duration"
      record_migration_version(connection, RUNTIME_VERSION)

      context.migrate(RECIPE_VERSION)

      assert_includes context.get_all_versions, RECIPE_VERSION
    end
  end

  test "repair migrations document irreversible rollback boundaries" do
    with_isolated_database do
      recipe_error = assert_raises(ActiveRecord::IrreversibleMigration) do
        NormalizeRecipeIngredientsAndEnrichRecipeInstructions.new.migrate(:down)
      end
      reconciliation_error = assert_raises(ActiveRecord::IrreversibleMigration) do
        ReconcileRuntimeAgentSessionAndGrantNullability.new.migrate(:down)
      end

      assert_match(/canonical ingredient merges/i, recipe_error.message)
      assert_match(/NULL session identifiers or grant issuers/i, reconciliation_error.message)
    end
  end

  private
    def with_isolated_database
      fixture_pool = ActiveRecord::Base.connection_pool

      result = Dir.mktmpdir([ "hearth-migration-#{Process.pid}-", "" ]) do |directory|
        database = File.join(directory, "repair.sqlite3")
        original_migration_verbosity = ActiveRecord::Migration.verbose
        isolated_pool = nil
        singleton = nil
        original_method = :migration_class_before_duplicated_version_repair
        migration_class_redirected = false

        begin
          ActiveRecord::Migration.verbose = false
          IsolatedMigrationBase.establish_connection(adapter: "sqlite3", database: database)
          isolated_pool = IsolatedMigrationBase.connection_pool
          database_tasks = ActiveRecord::Tasks::DatabaseTasks
          singleton = database_tasks.singleton_class
          singleton.alias_method original_method, :migration_class
          singleton.define_method(:migration_class) { IsolatedMigrationBase }
          migration_class_redirected = true

          migration_pool = database_tasks.migration_connection_pool
          resolved_database = File.join(File.realpath(File.dirname(database)), File.basename(database))
          assert_same isolated_pool, migration_pool
          assert_equal File.expand_path(database), File.expand_path(migration_pool.db_config.database)
          assert resolved_database.start_with?(File.realpath(directory) + File::SEPARATOR)
          refute_equal Rails.root.join("storage/test.sqlite3").expand_path.to_s, resolved_database
          refute_equal Rails.root.join("storage/development.sqlite3").expand_path.to_s, resolved_database

          schema_migration = ActiveRecord::SchemaMigration.new(isolated_pool)
          internal_metadata = ActiveRecord::InternalMetadata.new(isolated_pool)
          context = ActiveRecord::MigrationContext.new(
            Rails.application.config.paths["db/migrate"].to_a,
            schema_migration,
            internal_metadata
          )

          migration_pool.with_connection do |connection|
            yield connection, context, isolated_pool
          end
        ensure
          begin
            if migration_class_redirected
              singleton.alias_method :migration_class, original_method
              singleton.remove_method original_method
            end
            IsolatedMigrationBase.remove_connection if isolated_pool
            assert_nil IsolatedMigrationBase.connection_handler.retrieve_connection_pool(IsolatedMigrationBase.name)
          ensure
            ActiveRecord::Migration.verbose = original_migration_verbosity
          end
        end
      end

      assert_same fixture_pool, ActiveRecord::Base.connection_pool
      result
    end

    def recipe_migration(context)
      context.migrations.find { |migration| migration.version == RECIPE_VERSION }
    end

    def record_migration_version(connection, version)
      connection.execute("INSERT INTO schema_migrations (version) VALUES (#{connection.quote(version.to_s)})")
    end

    def schema_dump(pool)
      output = StringIO.new
      ActiveRecord::SchemaDumper.dump(pool, output, IsolatedMigrationBase)
      output.string
    end

    def assert_supported_final_state(connection)
      assert connection.table_exists?(:ingredients)
      assert connection.table_exists?(:recipe_instruction_ingredients)
      assert connection.column_exists?(:recipe_ingredients, :display_name)
      assert connection.column_exists?(:recipe_ingredients, :display_quantity)
      refute connection.column_exists?(:recipe_ingredients, :name)
      refute connection.column_exists?(:recipe_ingredients, :amount)
      assert connection.columns(:recipe_ingredients).find { |column| column.name == "ingredient_id" }.null == false
      assert connection.columns(:agent_sessions).find { |column| column.name == "external_session_id" }.null
      assert connection.columns(:agent_grants).find { |column| column.name == "issued_by_id" }.null
      expected_nutrients = Nutrient::DEFAULTS.map { |row| row.values_at(:key, :name, :unit, :category, :display_order).map(&:to_s) }
      actual_nutrients = connection.select_rows(<<~SQL.squish).map { |row| row.map(&:to_s) }
        SELECT key, name, unit, category, display_order
        FROM nutrients
        ORDER BY display_order
      SQL
      assert_equal expected_nutrients, actual_nutrients
    end

    def seed_legacy_recipe_rows(connection)
      now = Time.current
      connection.execute("PRAGMA ignore_check_constraints = ON")
      household_one = insert(connection, :households, name: "First", installation_key: 1, created_at: now, updated_at: now)
      household_two = insert(connection, :households, name: "Second", installation_key: 2, created_at: now, updated_at: now)
      connection.execute("PRAGMA ignore_check_constraints = OFF")

      recipe_one = insert(connection, :recipes,
        household_id: household_one,
        title: "One",
        source_name: "Test",
        provenance_status: "observed",
        created_at: now,
        updated_at: now)
      recipe_two = insert(connection, :recipes,
        household_id: household_two,
        title: "Two",
        source_name: "Test",
        provenance_status: "observed",
        created_at: now,
        updated_at: now)

      {
        mixed: insert_recipe_ingredient(connection, recipe_one, 1, "Olive Oil", "2 1/2", now),
        decimal: insert_recipe_ingredient(connection, recipe_one, 2, " olive  oil ", "0.75", now),
        unparseable: insert_recipe_ingredient(connection, recipe_one, 3, "Pepper", "to taste", now),
        fraction: insert_recipe_ingredient(connection, recipe_two, 1, "Olive Oil", "3/4", now)
      }
    ensure
      connection.execute("PRAGMA ignore_check_constraints = OFF") if connection
    end

    def insert_recipe_ingredient(connection, recipe_id, position, name, amount, now)
      insert(connection, :recipe_ingredients,
        recipe_id: recipe_id,
        position: position,
        name: name,
        amount: amount,
        created_at: now,
        updated_at: now)
    end

    def assert_recipe_backfill(connection, ids)
      rows = ids.transform_values do |id|
        connection.select_one(<<~SQL.squish)
          SELECT display_name, display_quantity, ingredient_id, quantity_numerator, quantity_denominator
          FROM recipe_ingredients
          WHERE id = #{connection.quote(id)}
        SQL
      end

      assert_equal "Olive Oil", rows[:mixed].fetch("display_name")
      assert_equal "2 1/2", rows[:mixed].fetch("display_quantity")
      assert_equal rows[:mixed].fetch("ingredient_id"), rows[:decimal].fetch("ingredient_id")
      refute_equal rows[:mixed].fetch("ingredient_id"), rows[:fraction].fetch("ingredient_id")
      assert_equal [ 5, 2 ], rows[:mixed].values_at("quantity_numerator", "quantity_denominator")
      assert_equal [ 3, 4 ], rows[:decimal].values_at("quantity_numerator", "quantity_denominator")
      assert_equal [ 3, 4 ], rows[:fraction].values_at("quantity_numerator", "quantity_denominator")
      assert_equal [ nil, nil ], rows[:unparseable].values_at("quantity_numerator", "quantity_denominator")
      assert_equal 3, connection.select_value("SELECT COUNT(*) FROM ingredients")
    end

    def seed_agent_rows(connection)
      now = Time.current
      household = insert(connection, :households, name: "Agent Household", installation_key: 1, created_at: now, updated_at: now)
      person = insert(connection, :people, household_id: household, name: "Agent Person", created_at: now, updated_at: now)
      user = insert(connection, :users,
        person_id: person,
        email_address: "migration@example.test",
        password_digest: "digest",
        created_at: now,
        updated_at: now)
      profile = insert(connection, :agent_profiles,
        household_id: household,
        name: "Migration Agent",
        executable_path: "/usr/bin/true",
        arguments: "[]",
        environment_keys: "[]",
        enabled: true,
        update_policy: "manual",
        created_at: now,
        updated_at: now)
      installation = insert(connection, :agent_installations,
        household_id: household,
        profile_id: profile,
        external_id: "installation",
        executable_path: "/usr/bin/true",
        protocol_version: 1,
        advertised_capabilities: "{}",
        authentication_methods: "[]",
        created_at: now,
        updated_at: now)
      conversation = insert(connection, :agent_conversations,
        household_id: household,
        person_id: person,
        profile_id: profile,
        title: "Migration",
        created_at: now,
        updated_at: now)
      agent_session = insert(connection, :agent_sessions,
        household_id: household,
        person_id: person,
        conversation_id: conversation,
        installation_id: installation,
        external_session_id: "external-session",
        advertised_capabilities: "{}",
        created_at: now,
        updated_at: now)
      grant = insert(connection, :agent_grants,
        household_id: household,
        person_id: person,
        conversation_id: conversation,
        agent_session_id: agent_session,
        issued_by_id: user,
        token_locator: "locator",
        token_digest: "digest",
        capability_groups: "[]",
        expires_at: now + 1.day,
        created_at: now,
        updated_at: now)
      message = insert(connection, :agent_messages,
        household_id: household,
        person_id: person,
        conversation_id: conversation,
        agent_session_id: agent_session,
        external_id: "message",
        role: "agent",
        body: "Still here",
        body_digest: "body-digest",
        created_at: now,
        updated_at: now)

      { session: agent_session, grant: grant, message: message }
    end

    def assert_agent_rows_survived(connection, ids)
      assert_equal ids[:session], connection.select_value("SELECT id FROM agent_sessions WHERE id = #{ids[:session]}")
      assert_equal ids[:grant], connection.select_value("SELECT id FROM agent_grants WHERE id = #{ids[:grant]}")
      assert_equal ids[:message], connection.select_value("SELECT id FROM agent_messages WHERE agent_session_id = #{ids[:session]}")
    end

    def assert_agent_session_rebuild_fidelity(connection)
      assert_equal %w[
        agent_sessions_authentication_status
        agent_sessions_mcp_authorization_status
        agent_sessions_nonnegative_recovery_attempts
        agent_sessions_status
      ], connection.check_constraints(:agent_sessions).map(&:name).sort

      inbound = connection.tables.filter_map do |table|
        connection.foreign_keys(table).filter_map do |foreign_key|
          [ table, Array(foreign_key.column).map(&:to_s) ] if foreign_key.to_table == "agent_sessions"
        end
      end.flatten(1)
      assert_equal [
        [ "agent_audit_events", %w[agent_session_id] ],
        [ "agent_grants", %w[agent_session_id] ],
        [ "agent_messages", %w[agent_session_id] ],
        [ "agent_permission_requests", %w[agent_session_id] ],
        [ "agent_tool_activities", %w[agent_session_id] ]
      ], inbound.sort
    end

    def insert(connection, table, attributes)
      columns = attributes.keys.map { |name| connection.quote_column_name(name) }.join(", ")
      values = attributes.values.map { |value| connection.quote(value) }.join(", ")
      connection.execute("INSERT INTO #{connection.quote_table_name(table)} (#{columns}) VALUES (#{values})")
      connection.select_value("SELECT last_insert_rowid()").to_i
    end
end
