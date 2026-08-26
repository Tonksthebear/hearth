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

  def create_workout_guide_sequence_exercise(
    name: "Imported hinge",
    files: [ [ "frame-a.png", "image/png" ], [ "frame-b.png", "image/png" ], [ "photo.jpg", "image/jpeg" ] ],
    frame_interval_ms: 700,
    targets: []
  )
    slug = name.parameterize
    exercise = households(:home).exercises.create!(
      name: name,
      modality: "strength",
      movement_pattern: "hinge",
      source_key: "workout_guide:#{slug}",
      source_version: "v1",
      source_snapshot: {
        "attribution" => {
          "creator" => "Workout Guide",
          "license" => "CC BY-SA 4.0",
          "source_name" => "Workout Guide"
        },
        "visuals" => {}
      }
    )
    visual = add_frame_sequence(
      exercise,
      files: files,
      alt_text: "#{name} animation frames.",
      frame_interval_ms: frame_interval_ms,
      source_key: "workout_guide:#{slug}:frames",
      provenance_status: "verified"
    )
    visual.sorted_items.each_with_index do |item, index|
      item.source_identifier = files.fetch(index).first
      item.source_checksum = "import-#{index}"
    end
    targets.each do |muscle, role|
      exercise.exercise_muscle_targets.build(muscle: muscle, role: role)
    end
    exercise.save!
    items_snapshot = visual.reload.sorted_items.map { |item|
      {
        "source_identifier" => item.source_identifier,
        "content_digest" => item.file.blob.checksum
      }
    }
    exercise.update!(
      source_snapshot: exercise.source_snapshot.merge(
        "visuals" => {
          visual.source_key => { "items" => items_snapshot }
        }
      )
    )
    exercise.reload
  end

  def create_workout_template_with(exercises, title:)
    template = households(:home).workout_templates.create!(
      title: title,
      provenance_status: "personal"
    )
    block = template.workout_blocks.create!(
      title: "Work",
      block_kind: "strength",
      dose_class: "strength",
      position: 1
    )
    Array(exercises).each.with_index(1) do |exercise, position|
      block.exercise_prescriptions.create!(
        exercise: exercise,
        position: position,
        performance_kind: "reps",
        sets_count: 1,
        rep_min: 5,
        rep_max: 5,
        dose_class: "strength"
      )
    end
    template
  end

  def start_training_session_from(template)
    TrainingSession.start_from(template: template, person: people(:one))
  end

  def catalog_attribution(**fields)
    {
      "creator" => fields[:creator],
      "creator_url" => fields[:creator_url],
      "license" => fields[:license],
      "license_url" => fields[:license_url],
      "source_name" => fields[:source_name],
      "source_url" => fields[:source_url],
      "change_note" => fields[:change_note]
    }.compact
  end

  def create_source_exercise(name:, source_key:, attribution: {})
    households(:home).exercises.create!(
      name: name,
      modality: "strength",
      movement_pattern: "hinge",
      source_key: source_key,
      source_snapshot: { "attribution" => attribution }
    )
  end

  def uncached_sql_count
    ActiveRecord::Base.uncached do
      ActiveRecord::Base.connection.clear_query_cache
      count = 0
      callback = lambda { |*| count += 1 }
      ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { yield }
      count
    end
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
