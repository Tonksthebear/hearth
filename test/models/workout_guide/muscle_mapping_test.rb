require "test_helper"
require "json"
require "yaml"

class WorkoutGuide::MuscleMappingTest < ActiveSupport::TestCase
  OVERRIDE_SLUGS = {
    "cat-cow-stretch" => [
      { key: "erector_spinae", role: "primary" },
      { key: "rectus_abdominis", role: "secondary" }
    ],
    "worlds-greatest-stretch" => [
      { key: "hip_flexors", role: "primary" },
      { key: "hamstrings", role: "secondary" },
      { key: "glutes", role: "secondary" }
    ],
    "leg-swings-stretch" => [
      { key: "hip_flexors", role: "primary" },
      { key: "hamstrings", role: "secondary" },
      { key: "quadriceps", role: "secondary" }
    ],
    "torso-twist-stretch" => [
      { key: "obliques", role: "primary" },
      { key: "erector_spinae", role: "secondary" }
    ]
  }.freeze

  test "cardio and mobility expand to zero targets" do
    assert_empty WorkoutGuide::MuscleMapping.expand("Cardio", role: :primary)
    assert_empty WorkoutGuide::MuscleMapping.expand("Mobility", role: :secondary)
  end

  test "quads as primary expands to one quadriceps primary" do
    targets = WorkoutGuide::MuscleMapping.expand("Quads", role: :primary)

    assert_equal [ { muscle: muscles(:quadriceps), role: "primary" } ], targets
  end

  test "posterior chain expands from the written primary and secondary lists" do
    primary = WorkoutGuide::MuscleMapping.expand("Posterior Chain", role: :primary)
    secondary = WorkoutGuide::MuscleMapping.expand("Posterior Chain", role: :secondary)

    assert_equal [
      { muscle: muscles(:glutes), role: "primary" },
      { muscle: muscles(:hamstrings), role: "primary" },
      { muscle: muscles(:erector_spinae), role: "secondary" }
    ], primary
    assert_equal [
      { muscle: muscles(:glutes), role: "secondary" },
      { muscle: muscles(:hamstrings), role: "secondary" },
      { muscle: muscles(:erector_spinae), role: "stabilizer" }
    ], secondary
  end

  test "an unknown source name raises and names the string" do
    error = assert_raises(ArgumentError) {
      WorkoutGuide::MuscleMapping.expand("Made Up Muscle", role: :primary)
    }
    assert_includes error.message, "Made Up Muscle"
  end

  test "all twenty three source names expand without raising" do
    assert_equal 23, source_names.size
    source_names.each do |name|
      WorkoutGuide::MuscleMapping.expand(name, role: :primary)
      WorkoutGuide::MuscleMapping.expand(name, role: :secondary)
    end
  end

  test "slug overrides return the written target lists and keep a primary" do
    OVERRIDE_SLUGS.each do |slug, expected|
      targets = WorkoutGuide::MuscleMapping.targets_for(
        slug:,
        primary_muscle: "Mobility",
        secondary_muscles: []
      )

      assert_equal expected, targets.map { |pair| { key: pair.fetch(:muscle).key, role: pair.fetch(:role) } }, slug
      assert targets.any? { |pair| pair.fetch(:role) == "primary" }, slug
    end
  end

  test "a slug with an override ignores passed source names" do
    targets = WorkoutGuide::MuscleMapping.targets_for(
      slug: "cat-cow-stretch",
      primary_muscle: "Quads",
      secondary_muscles: [ "Chest" ]
    )
    keys = targets.map { |pair| pair.fetch(:muscle).key }

    assert_equal %w[erector_spinae rectus_abdominis], keys
    refute_includes keys, "quadriceps"
    refute_includes keys, "chest"
  end

  test "a slug with no override falls through to name expansion" do
    record = record_for("sumo-deadlift")
    targets = WorkoutGuide::MuscleMapping.targets_for(
      slug: record.fetch("slug"),
      primary_muscle: record.fetch("primaryMuscle"),
      secondary_muscles: record.fetch("secondaryMuscles")
    )

    assert targets.any? { |pair| pair.fetch(:role) == "primary" }
    assert_equal muscles(:glutes), record_target(targets, "glutes").fetch(:muscle)
  end

  test "an unknown slug raises" do
    error = assert_raises(ArgumentError) {
      WorkoutGuide::MuscleMapping.targets_for(
        slug: "not-in-the-overrides",
        primary_muscle: "Quads",
        secondary_muscles: []
      )
    }
    assert_includes error.message, "not-in-the-overrides"
  end

  test "a repeated muscle key inside one override raises" do
    Dir.mktmpdir("muscle-mapping-") do |dir|
      path = Pathname(dir).join("overrides.yml")
      data = overrides
      data.fetch("exercises").fetch("cat-cow-stretch").fetch("muscle_targets") << {
        "muscle_key" => "erector_spinae",
        "role" => "secondary"
      }
      path.write(YAML.dump(data))

      error = assert_raises(ArgumentError) {
        WorkoutGuide::MuscleMapping.new(path:).targets_for(
          slug: "cat-cow-stretch",
          primary_muscle: "Mobility",
          secondary_muscles: []
        )
      }
      assert_includes error.message, "erector_spinae"
    end
  end

  test "sumo deadlift merges overlapping glutes to primary without a duplicate" do
    record = record_for("sumo-deadlift")
    targets = WorkoutGuide::MuscleMapping.targets_for(
      slug: record.fetch("slug"),
      primary_muscle: record.fetch("primaryMuscle"),
      secondary_muscles: record.fetch("secondaryMuscles")
    )
    keys = targets.map { |pair| pair.fetch(:muscle).key }

    assert_equal keys, keys.uniq
    assert_equal "primary", record_target(targets, "glutes").fetch(:role)
  end

  test "merged targets are ordered by display position" do
    record = record_for("sumo-deadlift")
    targets = WorkoutGuide::MuscleMapping.targets_for(
      slug: record.fetch("slug"),
      primary_muscle: record.fetch("primaryMuscle"),
      secondary_muscles: record.fetch("secondaryMuscles")
    )

    assert_equal targets.map { |pair| pair.fetch(:muscle).display_position },
      targets.map { |pair| pair.fetch(:muscle).display_position }.sort
  end

  test "every override muscle key names a seeded muscle row" do
    produced_keys = []
    overrides.fetch("muscle_aliases").each_value { |key| produced_keys << key }
    overrides.fetch("muscle_compounds").each_value do |entry|
      %w[as_primary as_secondary].each do |list_name|
        entry.fetch(list_name).each { |target| produced_keys << target.fetch("muscle_key") }
      end
    end
    overrides.fetch("exercises").each_value do |entry|
      next unless entry.key?("muscle_targets")

      entry.fetch("muscle_targets").each { |target| produced_keys << target.fetch("muscle_key") }
    end

    produced_keys.uniq.each do |key|
      assert Muscle.exists?(key:), key
    end
  end

  private
    def overrides
      YAML.safe_load(
        Rails.root.join("config/workout_guide_overrides.yml").read,
        permitted_classes: [],
        permitted_symbols: [],
        aliases: false
      )
    end

    def source_names
      (overrides.fetch("muscle_aliases").keys +
        overrides.fetch("muscle_compounds").keys +
        overrides.fetch("muscle_unmapped")).sort
    end

    def records
      @records ||= JSON.parse(Rails.root.join("vendor/workout_guide/manifest.json").read)
    end

    def record_for(slug)
      records.find { |record| record.fetch("slug") == slug } || flunk("Missing record: #{slug}")
    end

    def record_target(targets, key)
      targets.find { |pair| pair.fetch(:muscle).key == key } || flunk("Missing mapped muscle: #{key}")
    end
end
