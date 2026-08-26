require "test_helper"
require_relative "../test_helpers/exercise_visual_test_helper"

class ExerciseVisualTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include ExerciseVisualTestHelper

  test "normalizes positions and defaults a missing frame interval to 700" do
    exercise = create_catalog_exercise
    later = add_frame_sequence(exercise, position: 4, frame_interval_ms: nil, alt_text: "Later")
    earlier = add_image_visual(exercise, position: 9, alt_text: "Earlier")
    exercise.normalize_positions

    assert exercise.save
    assert_equal [ 1, 2 ], exercise.reload.exercise_visuals.map(&:position)
    assert_equal 700, later.reload.frame_interval_ms
    assert_nil earlier.reload.frame_interval_ms
  end

  test "accepts exact interval boundaries and rejects values outside the range" do
    exercise = create_catalog_exercise
    low = add_frame_sequence(exercise, frame_interval_ms: 100, alt_text: "Low")
    high = add_frame_sequence(exercise, frame_interval_ms: 5000, alt_text: "High")
    exercise.normalize_positions
    assert exercise.save

    too_low = add_frame_sequence(create_catalog_exercise(name: "Too low"), frame_interval_ms: 99, alt_text: "Too low")
    assert_not too_low.valid?
    too_high = add_frame_sequence(create_catalog_exercise(name: "Too high"), frame_interval_ms: 5001, alt_text: "Too high")
    assert_not too_high.valid?
    fractional = add_frame_sequence(create_catalog_exercise(name: "Fractional"), frame_interval_ms: 700.5, alt_text: "Fractional")
    assert_not fractional.valid?
  end

  test "requires a nil interval for image and video visuals" do
    image = add_image_visual(create_catalog_exercise(name: "Image interval"), alt_text: "Image")
    image.frame_interval_ms = 700
    assert_not image.valid?

    video = add_video_visual(create_catalog_exercise(name: "Video interval"), alt_text: "Video")
    video.frame_interval_ms = 700
    assert_not video.valid?
  end

  test "enforces kind-specific item counts" do
    image = add_image_visual(create_catalog_exercise(name: "Two images"), alt_text: "Image")
    attach_item(image, "frame-b.png", "image/png")
    assert_not image.valid?

    video = add_video_visual(create_catalog_exercise(name: "Two videos"), alt_text: "Video")
    attach_item(video, "clip.webm", "video/webm")
    assert_not video.valid?

    sequence = create_catalog_exercise(name: "One frame").exercise_visuals.build(
      kind: "frame_sequence",
      position: 1,
      alt_text: "Sequence",
      provenance_status: "personal"
    )
    attach_item(sequence, "frame-a.png", "image/png")
    assert_not sequence.valid?
  end

  test "preserves group identity and frame order across save and reload" do
    exercise = create_catalog_exercise
    visual = add_frame_sequence(exercise, alt_text: "Hinge sequence")
    exercise.save!

    reloaded = exercise.reload.exercise_visuals.sole
    assert_equal visual.id, reloaded.id
    assert_equal "frame_sequence", reloaded.kind
    assert_equal [ 1, 2 ], reloaded.exercise_visual_items.map(&:position)
    assert_equal %w[frame-a.png frame-b.png], reloaded.exercise_visual_items.map { |item| item.file.filename.to_s }
  end

  test "requires nonblank alt text and an exact provenance status" do
    visual = add_image_visual(create_catalog_exercise, alt_text: " ")
    assert_not visual.valid?

    unknown = add_image_visual(create_catalog_exercise(name: "Unknown provenance"), alt_text: "Known")
    unknown.provenance_status = "unsupported"
    assert_not unknown.valid?

    exercise = create_catalog_exercise(name: "Provenance defaults")
    add_image_visual(exercise, alt_text: "Defaulted")
    exercise.save!
    assert_equal "personal", exercise.exercise_visuals.sole.provenance_status

    %w[verified adapted observed].each do |status|
      named = create_catalog_exercise(name: "Status #{status}")
      add_image_visual(named, alt_text: status, provenance_status: status)
      assert named.save
      assert_equal status, named.exercise_visuals.sole.provenance_status
    end
  end

  test "persists caption attribution source identity and nested metadata" do
    exercise = create_catalog_exercise
    visual = add_image_visual(
      exercise,
      alt_text: "Source image",
      caption: "Start position",
      display_attribution: "Household photo",
      source_key: "hinge-start"
    )
    item = visual.exercise_visual_items.first
    item.source_identifier = "catalog:hinge-start"
    item.source_checksum = "source-checksum"
    item.source_metadata = { "width" => 64, "nested" => { "ok" => true } }
    exercise.save!

    visual.reload
    item.reload
    assert_equal "Start position", visual.caption
    assert_equal "Household photo", visual.display_attribution
    assert_equal "hinge-start", visual.source_key
    assert_equal "catalog:hinge-start", item.source_identifier
    assert_equal "source-checksum", item.source_checksum
    assert_equal({ "width" => 64, "nested" => { "ok" => true } }, item.source_metadata)
    assert_not_instance_of String, item.source_metadata
  end

  test "swaps persisted visuals without unique index collisions" do
    exercise = create_catalog_exercise
    first = add_image_visual(exercise, alt_text: "First")
    second = add_image_visual(exercise, alt_text: "Second")
    exercise.save!

    first.position = 2
    second.position = 1
    assert exercise.save
    assert_equal [ second.id, first.id ], exercise.reload.exercise_visuals.map(&:id)
    assert_equal [ 1, 2 ], exercise.exercise_visuals.map(&:position)
  end

  test "swaps persisted frames inside a sequence without unique index collisions" do
    exercise = create_catalog_exercise
    visual = add_frame_sequence(exercise, alt_text: "Swap frames")
    exercise.save!
    first, second = visual.exercise_visual_items.to_a

    first.position = 2
    second.position = 1
    assert visual.save
    assert_equal [ second.id, first.id ], visual.reload.exercise_visual_items.map(&:id)
    assert_equal [ 1, 2 ], visual.exercise_visual_items.map(&:position)
  end

  test "compacts remaining visual positions after a persisted destroy" do
    exercise = create_catalog_exercise
    first = add_image_visual(exercise, alt_text: "Keep first")
    middle = add_image_visual(exercise, alt_text: "Remove middle")
    last = add_image_visual(exercise, alt_text: "Keep last")
    exercise.save!

    middle.mark_for_destruction
    exercise.normalize_positions
    assert exercise.save
    assert_equal [ first.id, last.id ], exercise.reload.exercise_visuals.map(&:id)
    assert_equal [ 1, 2 ], exercise.exercise_visuals.map(&:position)
  end

  test "compacts remaining frame positions after a persisted destroy" do
    exercise = create_catalog_exercise
    visual = add_frame_sequence(
      exercise,
      files: [ [ "frame-a.png", "image/png" ], [ "frame-b.png", "image/png" ], [ "photo.jpg", "image/jpeg" ] ],
      alt_text: "Three frames"
    )
    exercise.save!
    first, middle, last = visual.exercise_visual_items.to_a

    middle.mark_for_destruction
    visual.normalize_positions
    assert visual.save
    assert_equal [ first.id, last.id ], visual.reload.exercise_visual_items.map(&:id)
    assert_equal [ 1, 2 ], visual.exercise_visual_items.map(&:position)
  end

  test "rotates three persisted records at each ordered level" do
    exercise = create_catalog_exercise
    first = add_image_visual(exercise, alt_text: "A")
    second = add_image_visual(exercise, alt_text: "B")
    third = add_image_visual(exercise, alt_text: "C")
    exercise.save!

    first.position = 2
    second.position = 3
    third.position = 1
    assert exercise.save
    assert_equal [ third.id, first.id, second.id ], exercise.reload.exercise_visuals.map(&:id)

    visual = add_frame_sequence(
      create_catalog_exercise(name: "Rotate frames"),
      files: [ [ "frame-a.png", "image/png" ], [ "frame-b.png", "image/png" ], [ "photo.jpg", "image/jpeg" ] ],
      alt_text: "Rotate frames"
    )
    visual.exercise.save!
    one, two, three = visual.exercise_visual_items.to_a
    one.position = 2
    two.position = 3
    three.position = 1
    assert visual.save
    assert_equal [ three.id, one.id, two.id ], visual.reload.exercise_visual_items.map(&:id)
  end

  test "destroying an exercise without prescriptions removes visuals items attachments and unshared blobs" do
    exercise = create_catalog_exercise
    add_image_visual(exercise, alt_text: "Solo image")
    exercise.save!
    visual = exercise.exercise_visuals.sole
    item = visual.exercise_visual_items.sole
    blob = item.file.blob
    blob_key = blob.key

    perform_enqueued_jobs do
      exercise.destroy!
    end

    assert_not ExerciseVisual.exists?(visual.id)
    assert_not ExerciseVisualItem.exists?(item.id)
    assert_not ActiveStorage::Attachment.exists?(record_type: "ExerciseVisualItem", record_id: item.id)
    assert_not ActiveStorage::Blob.exists?(blob.id)
    assert_not blob.service.exist?(blob_key)
  end

  test "destroying an exercise leaves a blob that still has another attachment" do
    first_exercise = create_catalog_exercise(name: "Shared owner")
    second_exercise = create_catalog_exercise(name: "Shared survivor")
    first_visual = add_image_visual(first_exercise, alt_text: "Shared first")
    first_exercise.save!
    blob = first_visual.exercise_visual_items.sole.file.blob

    second_visual = second_exercise.exercise_visuals.build(
      kind: "image",
      position: 1,
      alt_text: "Shared second",
      provenance_status: "personal"
    )
    second_item = second_visual.exercise_visual_items.build(position: 1)
    second_item.file.attach(blob)
    second_exercise.save!

    perform_enqueued_jobs do
      first_exercise.destroy!
    end

    assert ActiveStorage::Blob.exists?(blob.id)
    assert blob.service.exist?(blob.key)
    assert second_item.reload.file.attached?
    assert_equal blob, second_item.file.blob
  end

  test "destroying a household removes the visual chain without a foreign key error" do
    connection = ActiveRecord::Base.connection
    connection.execute("PRAGMA ignore_check_constraints = ON")
    household_id = Household.insert_all!([ {
      name: "Teardown household",
      installation_key: 2,
      created_at: Time.current,
      updated_at: Time.current
    } ], returning: %w[id]).rows.first.first
    exercise_id = Exercise.insert_all!([ {
      household_id: household_id,
      name: "Teardown movement",
      modality: "strength",
      movement_pattern: "hinge",
      created_at: Time.current,
      updated_at: Time.current
    } ], returning: %w[id]).rows.first.first
    connection.execute("PRAGMA ignore_check_constraints = OFF")

    exercise = Exercise.find(exercise_id)
    add_image_visual(exercise, alt_text: "Teardown image")
    exercise.save!
    visual = exercise.exercise_visuals.sole
    item = visual.exercise_visual_items.sole

    perform_enqueued_jobs do
      assert Household.find(household_id).destroy
    end

    assert_not Exercise.exists?(exercise.id)
    assert_not ExerciseVisual.exists?(visual.id)
    assert_not ExerciseVisualItem.exists?(item.id)
  ensure
    connection&.execute("PRAGMA ignore_check_constraints = OFF")
  end

  test "unmodified_source_art is true only for an exact workout guide item list" do
    exercise = create_workout_guide_sequence_exercise
    visual = exercise.exercise_visuals.sole
    assert visual.unmodified_source_art?

    replaced = create_workout_guide_sequence_exercise(name: "Replaced hinge")
    replaced_visual = replaced.exercise_visuals.sole
    replaced_visual.sorted_items.first.file.attach(visual_upload("icon.svg", "image/svg+xml"))
    replaced_visual.save!
    assert_not replaced_visual.reload.unmodified_source_art?

    deleted = create_workout_guide_sequence_exercise(name: "Deleted hinge")
    deleted_visual = deleted.exercise_visuals.sole
    deleted_visual.sorted_items.last.destroy!
    assert_not deleted_visual.reload.unmodified_source_art?

    added = create_workout_guide_sequence_exercise(name: "Added hinge")
    added_visual = added.exercise_visuals.sole
    attach_item(added_visual, "icon.svg", "image/svg+xml", source_identifier: "extra")
    added_visual.normalize_positions
    added_visual.save!
    assert_not added_visual.reload.unmodified_source_art?

    reordered = create_workout_guide_sequence_exercise(name: "Reordered hinge")
    reordered_visual = reordered.exercise_visuals.sole
    first, second, third = reordered_visual.sorted_items
    first.position = 2
    second.position = 3
    third.position = 1
    reordered_visual.save!
    assert_not reordered_visual.reload.unmodified_source_art?
  end

  test "a prescription-protected exercise keeps its visuals when destroy is restricted" do
    exercise = exercises(:squat)
    add_image_visual(exercise, alt_text: "Protected image")
    exercise.save!
    visual_id = exercise.exercise_visuals.sole.id

    assert_raises(ActiveRecord::DeleteRestrictionError) do
      exercise.destroy
    end
    assert ExerciseVisual.exists?(visual_id)
  end
end
