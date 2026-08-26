require "test_helper"
require "fileutils"
require "json"
require "socket"

class WorkoutGuide::ImportTest < ActiveSupport::TestCase
  FIXTURE_ROOT = Rails.root.join("test/fixtures/files/workout_guide")
  BENCH_WITH_SOURCE = {
    "creator" => "Bryl Lim",
    "creator_url" => "https://bryllim.com",
    "license" => "CC BY-SA 4.0",
    "license_url" => "https://creativecommons.org/licenses/by-sa/4.0/",
    "source_name" => "Everkinetic",
    "source_url" => "https://github.com/everkinetic/data/blob/main/dist/svg/0042-tension.svg",
    "change_note" => "Rasterized on a transparent 512 × 512 canvas and recolored for monochrome display."
  }.freeze
  SUMO_WITHOUT_SOURCE = {
    "creator" => "Bryl Lim",
    "creator_url" => "https://bryllim.com",
    "license" => "CC BY-SA 4.0",
    "license_url" => "https://creativecommons.org/licenses/by-sa/4.0/",
    "source_name" => nil,
    "source_url" => nil,
    "change_note" => nil
  }.freeze

  test "a fresh import creates exercises, targets, one frame sequence, and three ordered items" do
    report = import!

    assert_equal 3, report.counts.fetch("created")
    exercise = find_imported("bench-press")
    assert_equal "Bench Press", exercise.name
    assert_equal "v1.0.0", exercise.source_version
    assert_equal [ 1, 2, 3 ], imported_visual(exercise).sorted_items.map(&:position)
    assert_equal bench_frame_paths, imported_visual(exercise).sorted_items.map(&:source_identifier)
    assert_equal Array.new(3, fixture_frame_digest), imported_visual(exercise).sorted_items.map(&:source_checksum)
  end

  test "modality movement pattern and equipment come from the reviewed overrides and source record" do
    import!

    exercise = find_imported("bench-press")
    assert_equal "strength", exercise.modality
    assert_equal "horizontal_push", exercise.movement_pattern
    assert_equal "Barbell", exercise.equipment
  end

  test "a compound muscle name expands and role precedence keeps the strongest role" do
    import!

    targets = target_pairs(find_imported("sumo-deadlift"))
    assert_includes targets, [ "glutes", "primary" ]
    assert_includes targets, [ "hamstrings", "primary" ]
    assert_includes targets, [ "erector_spinae", "secondary" ]
    assert_includes targets, [ "quadriceps", "secondary" ]
    assert_equal 1, targets.count { |key, _role| key == "glutes" }
  end

  test "a slug-level muscle_targets override replaces resolution" do
    import!

    assert_equal [
      [ "erector_spinae", "primary" ],
      [ "rectus_abdominis", "secondary" ]
    ], target_pairs(find_imported("cat-cow-stretch"))
  end

  test "an unmapped muscle name reports failed and creates no exercise" do
    report = nil
    assert_no_difference "Exercise.count" do
      with_bundle([ fixture_record("bench-press") ]) do |root|
        report = import!(root:, overrides_path: FIXTURE_ROOT.join("unmapped_overrides.yml"))
      end
    end

    assert_equal 1, report.counts.fetch("failed")
    assert_includes report.failures.sole.reasons.join, "Unmapped source muscle name"
    assert_nil find_imported("bench-press")
  end

  test "a record whose resolved targets carry no primary role reports failed" do
    record = fixture_record("bench-press").merge(
      "primaryMuscle" => "Cardio",
      "secondaryMuscles" => [ "Chest" ]
    )
    report = nil
    assert_no_difference "Exercise.count" do
      with_bundle([ record ]) do |root|
        report = import!(root:)
      end
    end

    assert_equal 1, report.counts.fetch("failed")
    assert_includes report.failures.sole.reasons.join, "primary role"
  end

  test "a second import reports every record as preserved and changes no attribute" do
    first = import!
    exercise = find_imported("bench-press")
    snapshot = exercise.source_snapshot.deep_dup
    visual_ids = imported_visual(exercise).sorted_items.map(&:id)

    second = import!
    exercise.reload
    assert_equal 3, second.counts.fetch("preserved")
    assert_equal 0, second.counts.fetch("created")
    assert_equal snapshot, exercise.source_snapshot
    assert_equal visual_ids, imported_visual(exercise).sorted_items.map(&:id)
    assert_equal first.results.filter_map { |result| result.exercise&.id }.sort, second.results.filter_map { |result| result.exercise&.id }.sort
  end

  test "a second import creates no new blobs for unchanged items" do
    import!
    assert_no_difference "ActiveStorage::Blob.count" do
      report = import!
      assert_equal 3, report.counts.fetch("preserved")
    end
  end

  test "every imported visual item owns its own blob row" do
    import!

    blob_ids = households(:home).exercises.from_source_namespace("workout_guide").flat_map { |exercise|
      imported_visual(exercise).exercise_visual_items.map { |item| item.file.blob.id }
    }
    assert_equal 9, blob_ids.size
    assert_equal blob_ids, blob_ids.uniq
  end

  test "a name collision reports skipped and leaves the existing exercise unchanged" do
    existing = households(:home).exercises.create!(
      name: "Bench Press",
      modality: "strength",
      movement_pattern: "horizontal_push",
      equipment: "Household bar"
    )

    report = import!
    skipped = report.results.find { |result| result.status == "skipped" }

    assert_not_nil skipped
    assert_nil skipped.exercise
    existing.reload
    assert_nil existing.source_key
    assert_equal "Household bar", existing.equipment
    assert_nil find_imported("bench-press")
    skipped_entry = report.skipped.find { |entry| entry["name"] == "Bench Press" }
    assert_equal "Bench Press", skipped_entry.fetch("colliding_name")
    assert_equal "workout_guide:bench-press", skipped_entry.fetch("source_key")
  end

  test "catalog listing omits keys already linked in the household" do
    import!
    listing = WorkoutGuide::Import.new(household: households(:home), bundle: FIXTURE_ROOT).catalog_listing

    assert_empty listing
  end

  test "a source record absent from a later bundle reports source_removed" do
    import!
    exercise = find_imported("cat-cow-stretch")

    with_bundle(fixture_records_except("cat-cow-stretch")) do |root|
      report = import!(root:)
      removed = report.results.find { |result| result.status == "source_removed" }

      assert_not_nil removed
      assert_equal exercise.id, removed.exercise.id
      assert exercise.reload.source_removed?
    end
  end

  test "a mid-record validation failure rolls back a target delete that already executed" do
    first_record = two_target_bench_press
    with_bundle([ first_record ]) do |root|
      report = import!(root:)
      assert_equal [ "created" ], report.results.map(&:status)
    end

    exercise = find_imported("bench-press")
    dropped = exercise.exercise_muscle_targets.find { |target| target.muscle.key == "triceps" }
    visual = imported_visual(exercise)
    item_ids = visual.sorted_items.map(&:id)
    blob_ids = visual.sorted_items.map { |item| item.file.blob.id }
    scalars = exercise.slice("name", "modality", "movement_pattern", "equipment")

    second_record = first_record.merge(
      "secondaryMuscles" => [],
      "frames" => [ first_record.fetch("frames").first ]
    )
    with_bundle([ second_record ]) do |root|
      report = import!(root:)
      result = report.results.find { |entry| entry.status == "failed" }

      assert_not_nil result
      assert_includes result.reasons.join, "must have at least two items"
    end

    assert ExerciseMuscleTarget.exists?(id: dropped.id)
    exercise.reload
    assert_equal scalars, exercise.slice("name", "modality", "movement_pattern", "equipment")
    assert_equal [ [ "chest", "primary" ], [ "triceps", "secondary" ] ], target_pairs(exercise)
    assert_equal item_ids, imported_visual(exercise).sorted_items.map(&:id)
    assert_equal blob_ids, imported_visual(exercise).sorted_items.map { |item| item.file.blob.id }
  end

  test "an updated three-way merge applies the upstream scalar and keeps the household edit" do
    import!
    exercise = find_imported("bench-press")
    exercise.update!(name: "Household bench")

    record = fixture_record("bench-press").merge("equipment" => "Dumbbell")
    with_bundle([ record ]) do |root|
      report = import!(root:)
      result = report.results.find { |entry| entry.exercise&.id == exercise.id }

      assert_equal "updated", result.status
      assert_equal "Household bench", result.exercise.name
      assert_equal "Dumbbell", result.exercise.equipment
    end
  end

  test "a missing reviewed override reports failed and creates no exercise" do
    record = fixture_record("bench-press").merge("slug" => "not-in-the-overrides", "name" => "Unknown Press")
    report = nil
    assert_no_difference "Exercise.count" do
      with_bundle([ record ]) do |root|
        report = import!(root:)
      end
    end

    assert_equal 1, report.counts.fetch("failed")
    assert_includes report.failures.sole.reasons.join, "Unknown workout guide exercise slug"
    assert_includes report.failures.sole.reasons.join, "not-in-the-overrides"
  end

  test "a scalar-only source update reuses existing blobs" do
    import!
    exercise = find_imported("bench-press")
    blob_ids = imported_visual(exercise).sorted_items.map { |item| item.file.blob.id }

    record = fixture_record("bench-press").merge("equipment" => "Smith machine")
    assert_no_difference "ActiveStorage::Blob.count" do
      with_bundle([ record ]) do |root|
        report = import!(root:)
        result = report.results.find { |entry| entry.exercise&.id == exercise.id }

        assert_equal "updated", result.status
        assert_equal "Smith machine", result.exercise.equipment
        assert_equal blob_ids, imported_visual(result.exercise).sorted_items.map { |item| item.file.blob.id }
      end
    end
  end

  test "source_snapshot attribution matches the exact seven-field hash" do
    import!

    assert_equal BENCH_WITH_SOURCE, find_imported("bench-press").source_snapshot.fetch("attribution")
    assert_equal SUMO_WITHOUT_SOURCE, find_imported("sumo-deadlift").source_snapshot.fetch("attribution")
  end

  test "a mapping-only pass over the vendored manifest resolves all slugs" do
    mapping = WorkoutGuide::MuscleMapping.default
    records = WorkoutGuide::Bundle.vendored.records

    assert_equal 302, records.size
    records.each do |record|
      targets = mapping.targets_for(
        slug: record.fetch("slug"),
        primary_muscle: record.fetch("primaryMuscle"),
        secondary_muscles: record.fetch("secondaryMuscles")
      )
      assert targets.any? { |pair| pair.fetch(:role) == "primary" }, record.fetch("slug")
    end
  end

  test "a fixture-bundle import opens no TCP sockets" do
    guard = ->(*) { raise "network" }

    with_stubbed_method(TCPSocket, :open, guard) do
      with_stubbed_method(TCPSocket, :new, guard) do
        with_stubbed_method(Socket, :tcp, guard) do
          report = import!
          assert_equal 3, report.counts.fetch("created")
        end
      end
    end
  end

  private
    def import!(root: FIXTURE_ROOT, overrides_path: WorkoutGuide::MuscleMapping::OVERRIDES_PATH)
      WorkoutGuide::Import.new(household: households(:home), bundle: root, overrides_path:).run
    end

    def find_imported(slug)
      households(:home).exercises.find_by(source_key: "workout_guide:#{slug}")
    end

    def imported_visual(exercise)
      exercise.exercise_visuals.sole
    end

    def target_pairs(exercise)
      exercise.exercise_muscle_targets.map { |target| [ target.muscle.key, target.role ] }
    end

    def fixture_records
      @fixture_records ||= JSON.parse(FIXTURE_ROOT.join("manifest.json").read)
    end

    def fixture_record(slug)
      fixture_records.find { |record| record.fetch("slug") == slug }.deep_dup
    end

    def fixture_records_except(slug)
      fixture_records.reject { |record| record.fetch("slug") == slug }.map(&:deep_dup)
    end

    def fixture_frame_digest
      WorkoutGuide::Bundle.new(FIXTURE_ROOT).checksum_for!("assets/bench-press/frame-1.png")
    end

    def bench_frame_paths
      (1..3).map { |index| "assets/bench-press/frame-#{index}.png" }
    end

    def two_target_bench_press
      fixture_record("bench-press").merge("secondaryMuscles" => [ "Triceps" ])
    end

    def with_bundle(records)
      Dir.mktmpdir("workout-guide-") do |dir|
        root = Pathname(dir).join("bundle")
        FileUtils.cp_r(FIXTURE_ROOT, root)
        root.join("manifest.json").write("#{JSON.pretty_generate(records)}\n")
        yield root
      end
    end
end
