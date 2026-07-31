require "test_helper"

class ActivityLibraryTest < ActiveSupport::TestCase
  test "prepares household catalog and selected person recovery configuration" do
    library = ActivityLibrary.new(household: households(:home), person: people(:one))

    assert_includes library.sections.find { |section| section.key == :workout_templates }.records, workout_templates(:balanced)
    assert_includes library.sections.find { |section| section.key == :exercises }.records, exercises(:squat)
    assert_includes library.sections.find { |section| section.key == :habits }.records, habits(:sauna)
    assert_includes library.sections.find { |section| section.key == :recovery }.records, person_habits(:alex_sauna)
    refute_includes library.sections.find { |section| section.key == :recovery }.records, person_habits(:sam_sauna)
  end
end
