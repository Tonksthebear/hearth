require "test_helper"
require_relative "../../test_helpers/exercise_visual_test_helper"

class Exercise::SourceMergeTest < ActiveSupport::TestCase
  include ExerciseVisualTestHelper

  test "creates a source-linked exercise and repeats as preserved" do
    result = merge_source!(source_record)

    assert_equal "created", result.status
    exercise = result.exercise
    assert exercise.source_linked?
    assert exercise.merges_automatically?
    assert_not exercise.source_removed?
    assert_equal "Catalog hinge", exercise.name
    assert_equal "Barbell", exercise.equipment
    assert_nil exercise.guidance
    assert_equal [ "glutes" ], exercise.exercise_muscle_targets.map { |target| target.muscle.key }
    assert_equal ATTRIBUTION, exercise.source_snapshot.fetch("attribution")

    repeat = merge_source!(source_record)
    assert_equal "preserved", repeat.status
    assert_equal exercise.id, repeat.exercise.id
  end

  test "a source_version change alone yields updated" do
    merge_source!(source_record)
    result = merge_source!(source_record.merge(source_version: "v2"))

    assert_equal "updated", result.status
    assert_equal "v2", result.exercise.source_version
    assert_equal "Catalog hinge", result.exercise.name
  end

  test "updates untouched scalars and never writes guidance" do
    created = merge_source!(source_record)
    created.exercise.update!(guidance: "Household cue")

    result = merge_source!(source_record.merge(
      modality: "mixed",
      equipment: "Kettlebell",
      guidance: "Upstream cue"
    ))

    assert_equal "updated", result.status
    assert_equal "mixed", result.exercise.modality
    assert_equal "Kettlebell", result.exercise.equipment
    assert_equal "Household cue", result.exercise.guidance
  end

  test "preserves a household-edited scalar and still advances the snapshot base" do
    created = merge_source!(source_record)
    created.exercise.update!(equipment: "Household bar")

    result = merge_source!(source_record.merge(equipment: "Trap bar"))

    assert_equal "updated", result.status
    assert_equal "Household bar", result.exercise.equipment
    assert_equal "Trap bar", result.exercise.source_snapshot.dig("scalars", "equipment")
  end

  test "applies a free upstream rename" do
    merge_source!(source_record)
    result = merge_source!(source_record.merge(name: "Romanian hinge"))

    assert_equal "updated", result.status
    assert_equal "Romanian hinge", result.exercise.name
    assert_equal "Romanian hinge", result.exercise.source_snapshot.dig("scalars", "name")
  end

  test "name conflict with another safe change yields updated and keeps the local name" do
    merge_source!(source_record)
    result = merge_source!(source_record.merge(
      name: exercises(:squat).name,
      equipment: "Trap bar"
    ))

    assert_equal "updated", result.status
    assert_includes result.reasons, "name_conflict"
    assert_equal "Catalog hinge", result.exercise.name
    assert_equal "Catalog hinge", result.exercise.source_snapshot.dig("scalars", "name")
    assert_equal "Trap bar", result.exercise.equipment
  end

  test "name conflict with no other change yields preserved" do
    merge_source!(source_record)
    result = merge_source!(source_record.merge(name: exercises(:squat).name))

    assert_equal "preserved", result.status
    assert_includes result.reasons, "name_conflict"
    assert_equal "Catalog hinge", result.exercise.name
    assert_equal "Catalog hinge", result.exercise.source_snapshot.dig("scalars", "name")
  end

  test "a later merge retries a conflicting rename once the name is freed" do
    merge_source!(source_record)
    merge_source!(source_record.merge(name: exercises(:squat).name, equipment: "Trap bar"))
    exercises(:squat).update!(name: "Renamed squat")

    result = merge_source!(source_record.merge(name: "Goblet squat", equipment: "Trap bar"))

    assert_equal "updated", result.status
    assert_equal "Goblet squat", result.exercise.name
    assert_equal "Goblet squat", result.exercise.source_snapshot.dig("scalars", "name")
  end

  test "skips when a household exercise already holds the source name" do
    assert_no_difference "Exercise.count" do
      result = merge_source!(source_record.merge(name: exercises(:squat).name))
      assert_equal "skipped", result.status
      assert_nil result.exercise
    end
    assert_nil households(:home).exercises.find_by(source_key: "catalog-hinge")
  end

  test "adds an incoming target and leaves a household-added target untouched" do
    created = merge_source!(source_record)
    created.exercise.exercise_muscle_targets.create!(muscle: muscles(:calves), role: :stabilizer)

    result = merge_source!(source_record.merge(targets: {
      "glutes" => "primary",
      "hamstrings" => "secondary"
    }))

    keys = result.exercise.exercise_muscle_targets.map { |target| [ target.muscle.key, target.role ] }
    assert_includes keys, [ "glutes", "primary" ]
    assert_includes keys, [ "hamstrings", "secondary" ]
    assert_includes keys, [ "calves", "stabilizer" ]
  end

  test "a household-removed target stays removed across two later merges" do
    created = merge_source!(source_record.merge(targets: {
      "glutes" => "primary",
      "hamstrings" => "secondary"
    }))
    created.exercise.exercise_muscle_targets.find { |target| target.muscle.key == "hamstrings" }.destroy!

    incoming = source_record.merge(targets: { "glutes" => "primary", "hamstrings" => "secondary" })
    first = merge_source!(incoming)
    second = merge_source!(incoming)

    assert_equal [ "glutes" ], first.exercise.exercise_muscle_targets.map { |target| target.muscle.key }
    assert_equal [ "glutes" ], second.exercise.exercise_muscle_targets.map { |target| target.muscle.key }
    assert_includes first.exercise.source_snapshot.fetch("removed_target_keys"), "hamstrings"
    assert_includes second.exercise.source_snapshot.fetch("removed_target_keys"), "hamstrings"
  end

  test "removes an obsolete source target and preserves a household-changed source target" do
    created = merge_source!(source_record.merge(targets: {
      "glutes" => "primary",
      "hamstrings" => "secondary",
      "quadriceps" => "primary"
    }))
    created.exercise.exercise_muscle_targets.find { |target| target.muscle.key == "glutes" }.update!(role: :stabilizer)

    result = merge_source!(source_record.merge(targets: { "glutes" => "primary" }))

    keys = result.exercise.exercise_muscle_targets.map { |target| [ target.muscle.key, target.role ] }
    assert_includes keys, [ "glutes", "stabilizer" ]
    assert_not keys.any? { |key, _role| key == "hamstrings" }
    assert_not keys.any? { |key, _role| key == "quadriceps" }
  end

  test "preserves a household file edit when source_checksum stays stale" do
    created = merge_source!(source_record.merge(visuals: [ image_visual ]))
    item = created.exercise.exercise_visuals.sole.exercise_visual_items.sole
    original_blob = item.file.blob
    item.file.attach(visual_upload("icon.svg", "image/svg+xml"))
    item.save!
    item.reload

    result = merge_source!(source_record.merge(visuals: [ image_visual(alt_text: "Upstream start") ]))
    visual = result.exercise.exercise_visuals.sole
    reloaded = visual.exercise_visual_items.sole

    assert_equal "Start", visual.alt_text
    assert_equal "Ready", visual.caption
    assert_equal "sum-a", reloaded.source_checksum
    assert_not_equal original_blob.checksum, reloaded.file.blob.checksum
    assert_equal reloaded.file.blob.id, item.reload.file.blob.id
  end

  test "preserves an equal-content local reorder when upstream metadata changes" do
    created = merge_source!(source_record.merge(visuals: [ sequence_visual ]))
    visual = created.exercise.exercise_visuals.sole
    first, second = visual.exercise_visual_items.to_a
    first.position = 2
    second.position = 1
    assert visual.save

    result = merge_source!(source_record.merge(visuals: [ sequence_visual(alt_text: "Upstream frames") ]))
    reloaded = result.exercise.exercise_visuals.sole

    assert_equal "Frame sequence", reloaded.alt_text
    assert_equal [ second.id, first.id ], reloaded.exercise_visual_items.map(&:id)
    assert_equal [ 1, 2 ], reloaded.exercise_visual_items.map(&:position)
  end

  test "visual lifecycle A records a household deletion tombstone across later merges" do
    created = merge_source!(source_record.merge(visuals: [ image_visual ]))
    created.exercise.exercise_visuals.sole.destroy!

    first = merge_source!(source_record.merge(visuals: [ image_visual ]))
    second = merge_source!(source_record.merge(visuals: [ image_visual ]))

    assert_equal 0, first.exercise.exercise_visuals.count
    assert_equal 0, second.exercise.exercise_visuals.count
    assert_includes first.exercise.source_snapshot.fetch("removed_visual_keys"), "hinge-start"
    assert_includes second.exercise.source_snapshot.fetch("removed_visual_keys"), "hinge-start"
  end

  test "visual lifecycle B destroys an untouched upstream-removed visual without a tombstone" do
    merge_source!(source_record.merge(visuals: [ image_visual ]))
    result = merge_source!(source_record.merge(visuals: []))

    assert_equal 0, result.exercise.exercise_visuals.count
    assert_equal({}, result.exercise.source_snapshot.fetch("visuals"))
    assert_not_includes result.exercise.source_snapshot.fetch("removed_visual_keys"), "hinge-start"
  end

  test "visual lifecycle C restores an upstream visual unless a household tombstone exists" do
    created = merge_source!(source_record.merge(visuals: [
      image_visual,
      image_visual(source_key: "hinge-finish", checksum: "sum-finish", alt_text: "Finish")
    ]))
    created.exercise.exercise_visuals.find_by!(source_key: "hinge-finish").destroy!
    merge_source!(source_record.merge(visuals: [
      image_visual,
      image_visual(source_key: "hinge-finish", checksum: "sum-finish", alt_text: "Finish")
    ]))
    merge_source!(source_record.merge(visuals: [
      image_visual(source_key: "hinge-finish", checksum: "sum-finish", alt_text: "Finish")
    ]))

    result = merge_source!(source_record.merge(visuals: [
      image_visual,
      image_visual(source_key: "hinge-finish", checksum: "sum-finish", alt_text: "Finish")
    ]))

    keys = result.exercise.exercise_visuals.map(&:source_key)
    assert_includes keys, "hinge-start"
    assert_not_includes keys, "hinge-finish"
    assert_includes result.exercise.source_snapshot.fetch("removed_visual_keys"), "hinge-finish"
    assert_not_includes result.exercise.source_snapshot.fetch("removed_visual_keys"), "hinge-start"
  end

  test "visual lifecycle D preserves a household-modified visual when upstream removes it" do
    created = merge_source!(source_record.merge(visuals: [ image_visual ]))
    visual = created.exercise.exercise_visuals.sole
    visual.update!(alt_text: "Household start")

    result = merge_source!(source_record.merge(visuals: []))
    reloaded = result.exercise.exercise_visuals.sole

    assert_equal visual.id, reloaded.id
    assert_equal "Household start", reloaded.alt_text
    assert_not_includes result.exercise.source_snapshot.fetch("removed_visual_keys"), "hinge-start"
    assert result.exercise.source_snapshot.fetch("visuals").key?("hinge-start")

    returned = merge_source!(source_record.merge(visuals: [ image_visual(alt_text: "Upstream start") ]))
    assert_equal "Household start", returned.exercise.exercise_visuals.sole.alt_text
  end

  test "preserves a household-changed source visual for item count alt caption and frame interval" do
    created = merge_source!(source_record.merge(visuals: [ sequence_visual ]))
    visual = created.exercise.exercise_visuals.sole
    attach_item(visual, "photo.jpg", "image/jpeg", source_identifier: "extra")
    visual.update!(alt_text: "Household frames", caption: "Household caption", frame_interval_ms: 900)

    result = merge_source!(source_record.merge(visuals: [ sequence_visual(
      alt_text: "Upstream frames",
      caption: "Upstream caption",
      frame_interval_ms: 400
    ) ]))
    reloaded = result.exercise.exercise_visuals.sole

    assert_equal "Household frames", reloaded.alt_text
    assert_equal "Household caption", reloaded.caption
    assert_equal 900, reloaded.frame_interval_ms
    assert_equal 3, reloaded.exercise_visual_items.count
  end

  test "leaves a household-added visual untouched" do
    created = merge_source!(source_record.merge(visuals: [ image_visual ]))
    household_visual = add_image_visual(created.exercise, alt_text: "Household photo")
    created.exercise.normalize_positions
    created.exercise.save!

    result = merge_source!(source_record.merge(visuals: [ image_visual(alt_text: "Upstream start") ]))
    visuals = result.exercise.exercise_visuals.sort_by(&:position)

    assert_equal [ "hinge-start", nil ], visuals.map(&:source_key)
    assert_equal "Upstream start", visuals.first.alt_text
    assert_equal household_visual.id, visuals.last.id
    assert_equal "Household photo", visuals.last.alt_text
  end

  test "an unchanged item keeps its blob and a merge-driven attach refreshes the digest base" do
    created = merge_source!(source_record.merge(visuals: [ image_visual ]))
    blob_id = created.exercise.exercise_visuals.sole.exercise_visual_items.sole.file.blob.id

    unchanged = merge_source!(source_record.merge(visuals: [ image_visual ]))
    assert_equal "preserved", unchanged.status
    assert_equal blob_id, unchanged.exercise.exercise_visuals.sole.exercise_visual_items.sole.file.blob.id

    replaced = merge_source!(source_record.merge(visuals: [ image_visual(filename: "photo.jpg", content_type: "image/jpeg", checksum: "sum-b") ]))
    item = replaced.exercise.exercise_visuals.sole.exercise_visual_items.sole
    digest = replaced.exercise.source_snapshot.dig("visuals", "hinge-start", "items", 0, "content_digest")
    assert_equal item.file.blob.checksum, digest
    assert_not_equal blob_id, item.file.blob.id

    follow_up = merge_source!(source_record.merge(visuals: [ image_visual(filename: "photo.jpg", content_type: "image/jpeg", checksum: "sum-b") ]))
    assert_equal "preserved", follow_up.status

    applied = merge_source!(source_record.merge(visuals: [ image_visual(
      filename: "photo.jpg",
      content_type: "image/jpeg",
      checksum: "sum-b",
      alt_text: "After refresh"
    ) ]))
    assert_equal "updated", applied.status
    assert_equal "After refresh", applied.exercise.exercise_visuals.sole.alt_text
  end

  test "source removal keeps data and references then a return resumes merging" do
    created = merge_source!(source_record)
    exercise = created.exercise
    prescription = exercise_prescriptions(:squat_sets).dup
    prescription.exercise = exercise
    prescription.position = 2
    prescription.save!
    session_row = training_session_exercises(:sunday_squat).dup
    session_row.exercise = exercise
    session_row.position = 2
    session_row.save!

    first = Exercise.mark_sources_removed!(household: households(:home), present_source_keys: [])
    removed = exercise.reload

    assert_equal [ "source_removed" ], first.map(&:status)
    assert removed.source_removed?
    assert_not removed.merges_automatically?
    assert ExercisePrescription.exists?(id: prescription.id)
    assert TrainingSessionExercise.exists?(id: session_row.id)
    assert_equal "Catalog hinge", removed.name
    assert_equal 1, removed.exercise_muscle_targets.count

    retained_at = removed.source_removed_at
    second = Exercise.mark_sources_removed!(household: households(:home), present_source_keys: [])
    assert_equal [ "source_removed" ], second.map(&:status)
    assert_equal retained_at, exercise.reload.source_removed_at

    returned = merge_source!(source_record.merge(equipment: "Trap bar"))
    assert_equal "updated", returned.status
    assert_nil returned.exercise.source_removed_at
    assert returned.exercise.merges_automatically?
    assert_equal "Trap bar", returned.exercise.equipment
  end

  test "failed mapping rolls back a new record and a later item without source_identifier" do
    assert_no_difference [ "Exercise.count", "ExerciseMuscleTarget.count", "ExerciseVisual.count" ] do
      result = merge_source!(source_record.merge(
        source_key: "broken-create",
        visuals: [ image_visual.merge(items: [ { source_checksum: "sum-a", file: visual_upload("frame-a.png", "image/png") } ]) ]
      ))
      assert_equal "failed", result.status
    end

    created = merge_source!(source_record.merge(source_key: "broken-update"))
    assert_no_difference [ "ExerciseVisual.count", "ExerciseMuscleTarget.count" ] do
      result = merge_source!(source_record.merge(
        source_key: "broken-update",
        targets: { "glutes" => "primary", "hamstrings" => "secondary" },
        visuals: [ image_visual.merge(items: [ { source_checksum: "sum-a", file: visual_upload("frame-a.png", "image/png") } ]) ]
      ))
      assert_equal "failed", result.status
    end
    assert_equal [ "glutes" ], created.exercise.reload.exercise_muscle_targets.map { |target| target.muscle.key }
  end

  test "a household provenance_status edit survives a later merge" do
    created = merge_source!(source_record.merge(visuals: [ image_visual(provenance_status: "observed") ]))
    visual = created.exercise.exercise_visuals.sole
    assert_equal "observed", visual.provenance_status
    visual.update!(provenance_status: "adapted")

    result = merge_source!(source_record.merge(visuals: [ image_visual(alt_text: "Upstream start", provenance_status: "verified") ]))
    assert_equal "adapted", result.exercise.exercise_visuals.sole.provenance_status
  end

  test "source_key is unique within a household and nullable source keys remain allowed" do
    merge_source!(source_record)
    duplicate = households(:home).exercises.build(
      name: "Other hinge",
      modality: :strength,
      movement_pattern: :hinge,
      source_key: "catalog-hinge"
    )

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:source_key], "has already been taken"
    assert_nil exercises(:squat).source_key
    assert_nil exercises(:bike).source_key
    assert exercises(:squat).valid?
    assert exercises(:bike).valid?

    index = Exercise.connection.indexes(:exercises).find { |entry|
      entry.name == "index_exercises_on_household_id_and_source_key"
    }
    assert index.unique
    assert_equal [ "household_id", "source_key" ], index.columns
    assert_match(/source_key IS NOT NULL/, index.where)
  end

  private
    ATTRIBUTION = {
      "creator" => "Workout Guide",
      "creator_url" => "https://example.test/creator",
      "license" => "CC BY-SA 4.0",
      "license_url" => "https://creativecommons.org/licenses/by-sa/4.0/",
      "source_name" => "Workout Guide",
      "source_url" => "https://example.test/source",
      "change_note" => "Initial catalog import"
    }.freeze

    def merge_source!(record)
      Exercise.merge_source_record!(household: households(:home), record:)
    end

    def source_record(**overrides)
      {
        source_key: "catalog-hinge",
        source_version: "v1",
        name: "Catalog hinge",
        modality: "strength",
        movement_pattern: "hinge",
        equipment: "Barbell",
        targets: { "glutes" => "primary" },
        visuals: [],
        attribution: ATTRIBUTION,
        guidance: "Must never be imported"
      }.merge(overrides)
    end

    def image_visual(source_key: "hinge-start", filename: "frame-a.png", content_type: "image/png", checksum: "sum-a", **attributes)
      {
        source_key:,
        kind: "image",
        alt_text: "Start",
        caption: "Ready",
        frame_interval_ms: nil,
        provenance_status: "observed",
        items: [
          {
            source_identifier: "#{source_key}-1",
            source_checksum: checksum,
            file: visual_upload(filename, content_type)
          }
        ]
      }.merge(attributes)
    end

    def sequence_visual(**attributes)
      {
        source_key: "hinge-sequence",
        kind: "frame_sequence",
        alt_text: "Frame sequence",
        caption: "Catalog frames",
        frame_interval_ms: 700,
        provenance_status: "observed",
        items: [
          {
            source_identifier: "frame-1",
            source_checksum: "sum-1",
            file: visual_upload("frame-a.png", "image/png")
          },
          {
            source_identifier: "frame-2",
            source_checksum: "sum-2",
            file: visual_upload("frame-a.png", "image/png")
          }
        ]
      }.merge(attributes)
    end
end
