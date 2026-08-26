module WorkoutGuideImportTestHelper
  FIXTURE_ROOT = Rails.root.join("test/fixtures/files/workout_guide")

  def fixture_workout_guide_import(household: households(:home))
    WorkoutGuide::Import.new(household:, bundle: FIXTURE_ROOT)
  end

  def with_fixture_workout_guide_import
    original = WorkoutGuide::Import.method(:new)
    replacement = ->(household:, **) { original.call(household:, bundle: FIXTURE_ROOT) }
    with_stubbed_method(WorkoutGuide::Import, :new, replacement) { yield }
  end

  def with_import_started_during_record_for(household: households(:home))
    import = fixture_workout_guide_import(household:)
    original = import.method(:record_for)
    with_stubbed_method(import, :record_for, ->(source_key) {
      WorkoutGuide::ImportRun.start!(household:)
      original.call(source_key)
    }) do
      with_stubbed_method(WorkoutGuide::Import, :new, ->(**) { import }) { yield }
    end
  end

  def insert_foreign_exercise(name: "Foreign movement", source_key: nil)
    connection = ActiveRecord::Base.connection
    connection.execute("PRAGMA ignore_check_constraints = ON")
    other_household_id = Household.insert_all!([ {
      name: "Foreign install",
      installation_key: 3,
      created_at: Time.current,
      updated_at: Time.current
    } ], returning: %w[id]).rows.first.first
    attributes = {
      household_id: other_household_id,
      name:,
      modality: "strength",
      movement_pattern: "carry",
      created_at: Time.current,
      updated_at: Time.current
    }
    attributes[:source_key] = source_key if source_key
    Exercise.insert_all!([ attributes ], returning: %w[id]).rows.first.first
  ensure
    connection&.execute("PRAGMA ignore_check_constraints = OFF")
  end
end
