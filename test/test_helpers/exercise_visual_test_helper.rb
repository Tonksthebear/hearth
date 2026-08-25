module ExerciseVisualTestHelper
  def visual_upload(filename, content_type)
    Rack::Test::UploadedFile.new(file_fixture("exercises/#{filename}"), content_type)
  end

  def build_catalog_exercise(name: "Unassigned movement")
    households(:home).exercises.build(
      name: name,
      modality: "strength",
      movement_pattern: "hinge"
    )
  end

  def create_catalog_exercise(name: "Unassigned movement")
    build_catalog_exercise(name:).tap(&:save!)
  end

  def add_image_visual(exercise, filename: "frame-a.png", content_type: "image/png", **attributes)
    visual = exercise.exercise_visuals.build({
      kind: "image",
      position: next_visual_position(exercise),
      alt_text: "Image visual",
      provenance_status: "personal"
    }.merge(attributes))
    attach_item(visual, filename, content_type)
    visual
  end

  def add_video_visual(exercise, filename: "clip.mp4", content_type: "video/mp4", **attributes)
    visual = exercise.exercise_visuals.build({
      kind: "video",
      position: next_visual_position(exercise),
      alt_text: "Video visual",
      provenance_status: "personal"
    }.merge(attributes))
    attach_item(visual, filename, content_type)
    visual
  end

  def add_frame_sequence(exercise, files: [ [ "frame-a.png", "image/png" ], [ "frame-b.png", "image/png" ] ], **attributes)
    visual = exercise.exercise_visuals.build({
      kind: "frame_sequence",
      position: next_visual_position(exercise),
      alt_text: "Frame sequence",
      provenance_status: "personal",
      frame_interval_ms: attributes.key?(:frame_interval_ms) ? attributes.delete(:frame_interval_ms) : 700
    }.merge(attributes))
    files.each { |filename, content_type| attach_item(visual, filename, content_type) }
    visual
  end

  def attach_item(visual, filename, content_type, **attributes)
    item = visual.exercise_visual_items.build({
      position: visual.exercise_visual_items.size + 1
    }.merge(attributes))
    item.file.attach(visual_upload(filename, content_type))
    item
  end

  def oversized_blob(filename:, content_type:, bytes:)
    data = file_fixture("exercises/#{filename}").binread
    data << "\0" * (bytes - data.bytesize)
    ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new(data),
      filename: filename,
      content_type: content_type
    )
  end

  def exact_size_blob(filename:, content_type:, bytes:)
    oversized_blob(filename:, content_type:, bytes:)
  end

  private
    def next_visual_position(exercise)
      exercise.exercise_visuals.reject(&:marked_for_destruction?).size + 1
    end
end
