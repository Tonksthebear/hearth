# Run using bin/ci

release_root = "tmp/release-gate"
demo_database_env = [
  "RAILS_ENV=production",
  "SECRET_KEY_BASE=release-gate-secret",
  "HEARTH_DEMO_DATA=1",
  "HEARTH_DEMO_PASSWORD=release-gate-password",
  "HEARTH_STORAGE_ROOT=#{release_root}/demo_storage",
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
    recipe_instructions: 4, recipe_instruction_ingredients: 8, ingredients: 8,
    planned_meals: 3, meals: 2, meal_items: 4, recipe_feedbacks: 2,
    nutrients: 6, ingredient_nutrient_values: 24, recipe_nutrient_values: 0,
    meal_item_nutrient_values: 12, shopping_lists: 1, shopping_list_items: 9,
    shopping_list_item_sources: 12, exercises: 5, workout_templates: 2,
    workout_blocks: 4, exercise_prescriptions: 5, planned_workouts: 3,
    training_sessions: 2, training_session_blocks: 4,
    training_session_exercises: 5, training_sets: 12, habits: 3,
    habit_metrics: 2, person_habits: 4, person_habit_metrics: 3,
    habit_check_ins: 3, habit_check_in_measurements: 3,
    active_storage_blobs: 2, active_storage_attachments: 2
  }
  actual = expected.keys.index_with do |table|
    ActiveRecord::Base.connection.select_value("SELECT COUNT(*) FROM #{table}").to_i
  end
  raise "Unexpected demo counts: #{actual.inspect}" unless actual == expected
  alex = User.find_by!(email_address: "demo@example.com").person
  household = alex.household
  raise "Unexpected demo identity" unless household.name == "Hearth Demo"
  raise "Demo storage root escaped release isolation" unless
    Pathname.new(ActiveStorage::Blob.service.root).expand_path == Rails.root.join("tmp/release-gate/demo_storage")
  raise "Recipe covers missing" unless household.recipes.all? { |recipe| recipe.cover.attached? }
  raise "Recipe source presentation missing" unless household.recipes.pluck(:provenance_status).sort == %w[adapted personal]
  raise "Exercise performance kinds missing" unless ExercisePrescription.distinct.pluck(:performance_kind).sort == %w[count distance duration interval reps]
  raise "Workout lifecycle missing" unless household.planned_workouts.map(&:status).sort_by(&:to_s) == %i[completed in_progress planned]

  alex_meal = alex.meals.find_by!(eaten_on: Date.current)
  raise "Complete meal event missing" unless alex_meal.meal_items.size == 3 && alex_meal.meal_items.recipe.exists?
  raise "Recipe feedback missing" unless alex_meal.meal_items.recipe.first.recipe_feedback&.body.present?
  raise "Nutrition states missing" unless alex_meal.meal_items.map(&:nutrition_status).sort == [ "complete", "estimated", "unavailable" ]

  shopping_list = ShoppingList.existing_for(household:, date: Date.current)
  raise "Shopping lifecycle missing" unless shopping_list&.items&.any?(&:manual?) &&
    shopping_list.items.any?(&:completed?) && shopping_list.items.any?(&:user_managed?)
  raise "Shopping aggregation missing" unless shopping_list.items.any? { |item| item.shopping_list_item_sources.size == 2 }

  today = Person::Today.current(household:, person: alex)
  raise "Today workflow missing" unless today.sections.index_by(&:key).values_at(:up_next, :in_progress, :done).all? { |section| section.items.any? }
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
  raise "Expected nineteen reference muscles" unless Muscle.count == 19
  expected_storage_root = Rails.root.join("storage").to_s
  actual_storage_root = ActiveStorage::Blob.service.root.to_s
  raise "Active Storage root changed: #{actual_storage_root}" unless actual_storage_root == expected_storage_root
  puts "Production databases verified: #{configs.transform_values(&:database).inspect}"
  puts "Production Active Storage verified: #{actual_storage_root}"
RUBY
development_database_assertion = <<~'RUBY'
  configs = ActiveRecord::Base.configurations.configs_for(env_name: "development").index_by(&:name)
  expected_databases = {
    "primary" => Rails.root.join("storage/development.sqlite3").to_s,
    "cache" => Rails.root.join("storage/development_cache.sqlite3").to_s,
    "queue" => Rails.root.join("storage/development_queue.sqlite3").to_s,
    "cable" => Rails.root.join("storage/development_cable.sqlite3").to_s
  }
  actual_databases = configs.transform_values { |config| File.expand_path(config.database, Rails.root) }
  raise "Development database targets changed: #{actual_databases.inspect}" unless actual_databases == expected_databases
  raise "Development database targets collapsed" unless actual_databases.values.uniq.size == 4
  expected_paths = {
    "primary" => nil,
    "cache" => "db/cache_migrate",
    "queue" => "db/queue_migrate",
    "cable" => "db/cable_migrate"
  }
  actual_paths = configs.transform_values { |config| config.configuration_hash[:migrations_paths] }
  raise "Development migration paths changed: #{actual_paths.inspect}" unless actual_paths == expected_paths
  puts "Development databases verified: #{actual_databases.inspect}"
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

  step "Development gate: Verify default database isolation",
    "env", "-u", "DATABASE_URL", "-u", "PRIMARY_DATABASE_URL", "-u", "CACHE_DATABASE_URL",
    "-u", "QUEUE_DATABASE_URL", "-u", "CABLE_DATABASE_URL", "RAILS_ENV=development",
    "bin/rails", "runner", development_database_assertion

  step "Tests: Rails", "env", "HEARTH_REQUIRE_FOREMAN=1", "bin/rails", "test"
  step "Tests: System", "bin/system-test-browser", "bin/rails", "test:system"
  step "Tests: Agent chat cross-process acceptance", "bin/agent-chat-acceptance"

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
