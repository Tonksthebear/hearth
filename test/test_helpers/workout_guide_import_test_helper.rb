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
end
