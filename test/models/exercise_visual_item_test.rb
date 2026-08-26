require "test_helper"
require_relative "../test_helpers/exercise_visual_test_helper"

class ExerciseVisualItemTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include ExerciseVisualTestHelper

  test "accepts every allowed content type on a matching visual" do
    {
      "frame-a.png" => "image/png",
      "photo.jpg" => "image/jpeg",
      "photo.webp" => "image/webp",
      "photo.gif" => "image/gif",
      "icon.svg" => "image/svg+xml"
    }.each do |filename, content_type|
      exercise = create_catalog_exercise(name: "Image #{content_type}")
      add_image_visual(exercise, filename:, content_type:, alt_text: content_type)
      assert exercise.save, exercise.errors.full_messages.to_sentence
    end

    {
      "clip.mp4" => "video/mp4",
      "clip.webm" => "video/webm"
    }.each do |filename, content_type|
      exercise = create_catalog_exercise(name: "Video #{content_type}")
      add_video_visual(exercise, filename:, content_type:, alt_text: content_type)
      assert exercise.save, exercise.errors.full_messages.to_sentence
    end
  end

  test "rejects a plain text file" do
    exercise = create_catalog_exercise
    add_image_visual(exercise, filename: "notes.txt", content_type: "text/plain", alt_text: "Text")
    assert_not exercise.save
    assert exercise.exercise_visuals.first.exercise_visual_items.first.errors[:file].any?
  end

  test "reports inline renderability only for raster images" do
    exercise = create_catalog_exercise
    png = add_image_visual(exercise, filename: "frame-a.png", content_type: "image/png", alt_text: "PNG")
    jpeg = add_image_visual(create_catalog_exercise(name: "JPEG"), filename: "photo.jpg", content_type: "image/jpeg", alt_text: "JPEG")
    webp = add_image_visual(create_catalog_exercise(name: "WEBP"), filename: "photo.webp", content_type: "image/webp", alt_text: "WEBP")
    gif = add_image_visual(create_catalog_exercise(name: "GIF"), filename: "photo.gif", content_type: "image/gif", alt_text: "GIF")
    svg = add_image_visual(create_catalog_exercise(name: "SVG"), filename: "icon.svg", content_type: "image/svg+xml", alt_text: "SVG")
    mp4 = add_video_visual(create_catalog_exercise(name: "MP4"), filename: "clip.mp4", content_type: "video/mp4", alt_text: "MP4")
    webm = add_video_visual(create_catalog_exercise(name: "WEBM"), filename: "clip.webm", content_type: "video/webm", alt_text: "WEBM")

    assert png.exercise_visual_items.first.inline_renderable?
    assert jpeg.exercise_visual_items.first.inline_renderable?
    assert webp.exercise_visual_items.first.inline_renderable?
    assert gif.exercise_visual_items.first.inline_renderable?
    assert_not svg.exercise_visual_items.first.inline_renderable?
    assert_not mp4.exercise_visual_items.first.inline_renderable?
    assert_not webm.exercise_visual_items.first.inline_renderable?
  end

  test "accepts an image at exactly 10 MiB and rejects one extra byte" do
    accepted = exact_size_blob(filename: "frame-a.png", content_type: "image/png", bytes: ExerciseVisualItem::IMAGE_MAX_BYTES)
    rejected = exact_size_blob(filename: "frame-a.png", content_type: "image/png", bytes: ExerciseVisualItem::IMAGE_MAX_BYTES + 1)

    accepted_exercise = create_catalog_exercise(name: "Exact image")
    visual = accepted_exercise.exercise_visuals.build(kind: "image", position: 1, alt_text: "Exact", provenance_status: "personal")
    visual.exercise_visual_items.build(position: 1).file.attach(accepted)
    assert accepted_exercise.save

    rejected_exercise = create_catalog_exercise(name: "Oversize image")
    rejected_visual = rejected_exercise.exercise_visuals.build(kind: "image", position: 1, alt_text: "Oversize", provenance_status: "personal")
    rejected_visual.exercise_visual_items.build(position: 1).file.attach(rejected)
    assert_not rejected_exercise.save
  ensure
    rejected&.purge
  end

  test "accepts a video at exactly 50 MiB and rejects one extra byte" do
    accepted = exact_size_blob(filename: "clip.mp4", content_type: "video/mp4", bytes: ExerciseVisualItem::VIDEO_MAX_BYTES)
    rejected = exact_size_blob(filename: "clip.mp4", content_type: "video/mp4", bytes: ExerciseVisualItem::VIDEO_MAX_BYTES + 1)

    accepted_exercise = create_catalog_exercise(name: "Exact video")
    visual = accepted_exercise.exercise_visuals.build(kind: "video", position: 1, alt_text: "Exact", provenance_status: "personal")
    visual.exercise_visual_items.build(position: 1).file.attach(accepted)
    assert accepted_exercise.save

    rejected_exercise = create_catalog_exercise(name: "Oversize video")
    rejected_visual = rejected_exercise.exercise_visuals.build(kind: "video", position: 1, alt_text: "Oversize", provenance_status: "personal")
    rejected_visual.exercise_visual_items.build(position: 1).file.attach(rejected)
    assert_not rejected_exercise.save
  ensure
    rejected&.purge
  end

  test "rejects a video file inside an image visual" do
    exercise = create_catalog_exercise
    add_image_visual(exercise, filename: "clip.mp4", content_type: "video/mp4", alt_text: "Wrong kind")
    assert_not exercise.save
  end

  test "preserve_file_for_form persists a staged blob and returns a signed id" do
    exercise = build_catalog_exercise
    visual = add_image_visual(exercise, alt_text: "Staged")
    item = visual.exercise_visual_items.first

    assert_difference "ActiveStorage::Blob.count", 1 do
      item.preserve_file_for_form
    end

    signed_id = item.file_signed_id
    assert_predicate signed_id, :present?
    assert_equal item.file.blob, ActiveStorage::Blob.find_signed!(signed_id)
  end

  test "replacement detaches and purges the old blob" do
    exercise = create_catalog_exercise
    add_image_visual(exercise, alt_text: "Replace")
    exercise.save!
    item = exercise.exercise_visuals.sole.exercise_visual_items.sole
    old_blob = item.file.blob

    perform_enqueued_jobs do
      item.file.attach(visual_upload("frame-b.png", "image/png"))
      item.save!
    end

    assert_not ActiveStorage::Blob.exists?(old_blob.id)
    assert_not old_blob.service.exist?(old_blob.key)
    assert_equal "frame-b.png", item.reload.file.filename.to_s
  end

  test "removal through destroy detaches and purges an unshared blob" do
    exercise = create_catalog_exercise
    add_image_visual(exercise, alt_text: "Remove")
    exercise.save!
    item = exercise.exercise_visuals.sole.exercise_visual_items.sole
    blob = item.file.blob

    perform_enqueued_jobs do
      item.destroy!
    end

    assert_not ActiveStorage::Blob.exists?(blob.id)
    assert_not blob.service.exist?(blob.key)
  end

  test "last attachment removal leaves neither blob record nor stored file" do
    exercise = create_catalog_exercise
    add_image_visual(exercise, alt_text: "Last")
    exercise.save!
    item = exercise.exercise_visuals.sole.exercise_visual_items.sole
    blob = item.file.blob
    key = blob.key

    perform_enqueued_jobs do
      item.destroy!
    end

    assert_not ActiveStorage::Blob.exists?(blob.id)
    assert_not blob.service.exist?(key)
  end

  test "shared attachment removal leaves the blob and surviving item intact" do
    first = create_catalog_exercise(name: "Share first")
    second = create_catalog_exercise(name: "Share second")
    add_image_visual(first, alt_text: "First share")
    first.save!
    blob = first.exercise_visuals.sole.exercise_visual_items.sole.file.blob

    second_visual = second.exercise_visuals.build(kind: "image", position: 1, alt_text: "Second share", provenance_status: "personal")
    second_item = second_visual.exercise_visual_items.build(position: 1)
    second_item.file.attach(blob)
    second.save!

    perform_enqueued_jobs do
      first.exercise_visuals.sole.exercise_visual_items.sole.destroy!
    end

    assert ActiveStorage::Blob.exists?(blob.id)
    assert blob.service.exist?(blob.key)
    assert second_item.reload.file.attached?
    assert_equal blob, second_item.file.blob
  end

  test "thumbnail_rendering uses the explicit content-type list and never blob.variable?" do
    {
      "frame-a.png" => [ "image/png", :variant ],
      "photo.jpg" => [ "image/jpeg", :variant ],
      "photo.webp" => [ "image/webp", :variant ],
      "animated.gif" => [ "image/gif", :original ],
      "icon.svg" => [ "image/svg+xml", :placeholder ]
    }.each do |filename, (content_type, expected)|
      exercise = create_catalog_exercise(name: "Thumb #{content_type}")
      visual = add_image_visual(exercise, filename:, content_type:, alt_text: content_type)
      item = visual.exercise_visual_items.first
      assert_equal expected, item.thumbnail_rendering, content_type
      if content_type == "image/gif"
        assert item.file.blob.variable?
        assert_equal :original, item.thumbnail_rendering
      end
    end

    {
      "clip.mp4" => "video/mp4",
      "clip.webm" => "video/webm"
    }.each do |filename, content_type|
      exercise = create_catalog_exercise(name: "Thumb #{content_type}")
      visual = add_video_visual(exercise, filename:, content_type:, alt_text: content_type)
      assert_equal :placeholder, visual.exercise_visual_items.first.thumbnail_rendering
    end

    unattached = ExerciseVisualItem.new
    assert_equal :placeholder, unattached.thumbnail_rendering
  end
end
