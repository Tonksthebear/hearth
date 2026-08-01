# Run using bin/ci

release_root = "tmp/release-gate"
demo_database_env = [
  "RAILS_ENV=production",
  "SECRET_KEY_BASE=release-gate-secret",
  "HEARTH_DEMO_DATA=1",
  "HEARTH_DEMO_PASSWORD=release-gate-password",
  "DATABASE_URL=sqlite3:#{release_root}/demo.sqlite3",
  "CACHE_DATABASE_URL=sqlite3:#{release_root}/demo_cache.sqlite3",
  "QUEUE_DATABASE_URL=sqlite3:#{release_root}/demo_queue.sqlite3",
  "CABLE_DATABASE_URL=sqlite3:#{release_root}/demo_cable.sqlite3"
].freeze
production_database_env = [
  "-u", "HEARTH_DEMO_DATA",
  "-u", "HEARTH_DEMO_PASSWORD",
  "RAILS_ENV=production",
  "SECRET_KEY_BASE=release-gate-secret",
  "DATABASE_URL=sqlite3:#{release_root}/production.sqlite3",
  "CACHE_DATABASE_URL=sqlite3:#{release_root}/production_cache.sqlite3",
  "QUEUE_DATABASE_URL=sqlite3:#{release_root}/production_queue.sqlite3",
  "CABLE_DATABASE_URL=sqlite3:#{release_root}/production_cable.sqlite3"
].freeze
demo_assertion = <<~'RUBY'
  expected = {
    households: 1, people: 2, users: 1, recipes: 2, recipe_ingredients: 8,
    recipe_instructions: 4, planned_meals: 2, meals: 2, meal_items: 2,
    recipe_feedbacks: 0, nutrients: 6, ingredient_nutrient_values: 6,
    recipe_nutrient_values: 0, meal_item_nutrient_values: 0, exercises: 2,
    workout_templates: 1, workout_blocks: 2, exercise_prescriptions: 2,
    training_sessions: 1, training_session_blocks: 2,
    training_session_exercises: 2, training_sets: 3, habits: 2,
    habit_metrics: 2, person_habits: 3, person_habit_metrics: 3,
    habit_check_ins: 2, habit_check_in_measurements: 2
  }
  actual = expected.keys.index_with do |table|
    ActiveRecord::Base.connection.select_value("SELECT COUNT(*) FROM #{table}").to_i
  end
  raise "Unexpected demo counts: #{actual.inspect}" unless actual == expected
  raise "Unexpected demo identity" unless User.find_by!(email_address: "demo@hearth.local").person.household.name == "Hearth Demo"
  puts "Demo graph verified: #{actual.inspect}"
RUBY
production_database_assertion = <<~'RUBY'
  configs = ActiveRecord::Base.configurations.configs_for(env_name: "production").index_by(&:name)
  raise "Expected primary/cache/queue/cable" unless configs.keys.sort == %w[cable cache primary queue]
  raise "Database targets collapsed" unless configs.values.map(&:database).uniq.size == 4
  expected_paths = {
    "primary" => nil,
    "cache" => "db/cache_migrate",
    "queue" => "db/queue_migrate",
    "cable" => "db/cable_migrate"
  }
  actual_paths = configs.transform_values { |config| config.configuration_hash[:migrations_paths] }
  raise "Migration paths changed: #{actual_paths.inspect}" unless actual_paths == expected_paths
  active_storage_tables = %w[
    active_storage_attachments active_storage_blobs active_storage_variant_records
  ]
  missing_tables = active_storage_tables.reject { |table| ActiveRecord::Base.connection.table_exists?(table) }
  raise "Missing Active Storage tables: #{missing_tables.inspect}" if missing_tables.any?
  raise "Unexpected Active Storage service" unless Rails.application.config.active_storage.service == :local
  raise "Expected six reference nutrients" unless Nutrient.count == 6
  expected_storage_root = Rails.root.join("storage").to_s
  actual_storage_root = ActiveStorage::Blob.service.root.to_s
  raise "Active Storage root changed: #{actual_storage_root}" unless actual_storage_root == expected_storage_root
  puts "Production databases verified: #{configs.transform_values(&:database).inspect}"
  puts "Production Active Storage verified: #{actual_storage_root}"
RUBY
active_storage_write_assertion = <<~'RUBY'
  payload = "hearth release gate cover bytes\n"
  raise "Production database was not empty before the Active Storage check" if Household.exists? || User.exists?
  household = Household.create!(name: "Release gate household", installation_key: 1)
  recipe = household.recipes.create!(title: "Release gate recipe", provenance_status: :personal)
  recipe.cover.attach(
    io: StringIO.new(payload),
    filename: "release-gate.png",
    content_type: "image/png"
  )
  raise "Recipe cover was not attached" unless recipe.cover.attached?
  puts "Production Active Storage write verified: #{recipe.cover.blob.key}"
RUBY
active_storage_read_assertion = <<~'RUBY'
  payload = "hearth release gate cover bytes\n"
  recipe = Recipe.find_by(title: "Release gate recipe")
  household = recipe&.household
  begin
    raise "Release gate recipe was not persisted" unless recipe
    raise "Recipe cover attachment was not persisted" unless recipe.cover.attached?
    raise "Recipe cover bytes changed across processes" unless recipe.cover.download == payload
    puts "Production Active Storage independent-process byte round-trip verified"
  ensure
    recipe&.cover&.purge
    recipe&.destroy!
    household&.destroy!
  end
RUBY

CI.run do
  step "Setup", "bin/setup", "--skip-server"
  step "Release gate: Clean isolated databases",
    "ruby", "-rfileutils", "-e", "FileUtils.rm_rf(ARGV.fetch(0)); FileUtils.mkdir_p(ARGV.fetch(0))", release_root

  step "Style: Ruby", "bin/rubocop"

  step "Security: Gem audit", "bin/bundler-audit", "check", "--update"
  step "Security: Importmap vulnerability audit", "bin/importmap", "audit"
  step "Security: Brakeman code analysis", "bin/brakeman", "--quiet", "--no-pager", "--exit-on-warn", "--exit-on-error"

  step "Tests: Rails", "bin/rails", "test"
  step "Tests: System", "bin/system-test-browser", "bin/rails", "test:system"

  step "Release gate: Prepare isolated demo databases", "env", *demo_database_env, "bin/rails", "db:prepare"
  step "Release gate: Seed demo data", "env", *demo_database_env, "bin/rails", "db:seed"
  step "Release gate: Verify demo graph", "env", *demo_database_env, "bin/rails", "runner", demo_assertion
  step "Release gate: Seed demo data again", "env", *demo_database_env, "bin/rails", "db:seed"
  step "Release gate: Verify demo idempotency", "env", *demo_database_env, "bin/rails", "runner", demo_assertion

  step "Release gate: Prepare fresh production databases", "env", *production_database_env, "bin/rails", "db:prepare"
  step "Release gate: Migrate fresh production databases", "env", *production_database_env, "bin/rails", "db:migrate"
  step "Release gate: Verify production database isolation",
    "env", *production_database_env, "bin/rails", "runner", production_database_assertion
  step "Release gate: Write production Active Storage bytes",
    "env", *production_database_env, "bin/rails", "runner", active_storage_write_assertion
  step "Release gate: Read production Active Storage bytes in a new process",
    "env", *production_database_env, "bin/rails", "runner", active_storage_read_assertion
  step "Release gate: Precompile production assets",
    "env", "RAILS_ENV=production", "SECRET_KEY_BASE=release-gate-secret",
    "bin/rails", "assets:precompile", "assets:clobber"
  step "Release gate: Restore dynamic test assets", "bin/rails", "tailwindcss:build"
  step "Release gate: Eager load production",
    "env", "RAILS_ENV=production", "SECRET_KEY_BASE=release-gate-secret",
    "bin/rails", "runner", "Rails.application.eager_load!; puts \"Production eager load verified\""
end
