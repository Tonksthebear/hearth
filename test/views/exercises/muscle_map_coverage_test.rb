require "test_helper"
require "nokogiri"

class MuscleMapCoverageTest < ActionView::TestCase
  test "rendered map covers every seeded muscle key and draws hip flexors and groin" do
    exercise = households(:home).exercises.create!(
      name: "Coverage map",
      modality: "strength",
      movement_pattern: "hinge"
    )
    html = render partial: "exercises/muscle_map", locals: { muscle_map: MuscleMap.new(exercise) }
    rendered_keys = Nokogiri::HTML.fragment(html).css("[data-muscle-key]").map { |node| node["data-muscle-key"] }.uniq

    assert_empty Muscle::KEYS - rendered_keys - MuscleMap::UNMAPPED_KEYS
    assert_empty rendered_keys - Muscle::KEYS
    assert_includes rendered_keys, "hip_flexors"
    assert_includes rendered_keys, "groin"
    assert_not_includes MuscleMap::UNMAPPED_KEYS, "hip_flexors"
    assert_not_includes MuscleMap::UNMAPPED_KEYS, "groin"
  end
end
