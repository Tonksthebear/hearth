require "test_helper"
require_relative "../test_helpers/exercise_visual_test_helper"

class WorkoutTemplatesControllerTest < ActionDispatch::IntegrationTest
  include ExerciseVisualTestHelper
  test "renders provenance source safety copy and a production start path" do
    sign_in_as users(:one)

    get workout_template_path(workout_templates(:balanced))

    assert_response :success
    assert_select "h1", text: workout_templates(:balanced).title
    assert_select "p", text: /not clinical endorsement/i
    assert_select "p", text: /medical advice/i
    assert_select "form[action='#{training_sessions_path}']"
  end

  test "creates an ordered block and prescription graph" do
    sign_in_as users(:one)

    assert_difference({
      "WorkoutTemplate.count" => 1,
      "WorkoutBlock.count" => 1,
      "ExercisePrescription.count" => 1
    }) do
      post workout_templates_path, params: { workout_template: valid_template_params }
    end

    template = households(:home).workout_templates.find_by!(title: "Test template")
    assert_redirected_to workout_template_path(template)
    assert_equal [ 1 ], template.workout_blocks.pluck(:position)
    assert_equal [ 1 ], template.workout_blocks.first.exercise_prescriptions.pluck(:position)
    prescription = template.workout_blocks.first.exercise_prescriptions.first
    assert_predicate prescription, :per_side?
    assert_equal "3 sec lowering", prescription.tempo_cue
    assert_equal "bpm", prescription.target_heart_rate_unit
  end

  test "new renders one live selector and only nonempty native templates" do
    sign_in_as users(:one)

    get new_workout_template_path

    assert_response :success
    assert_select "el-select[name$='[performance_kind]'][value='reps']", count: 1
    assert_select "template[data-performance-fields-target='template'][data-kind='reps']", count: 1
    assert_select "template[data-kind='duration'], template[data-kind='distance'], template[data-kind='count'], template[data-kind='interval']", count: 0
    assert_select "el-select[name$='[target_distance_unit]'][disabled]", count: 1
    assert_select "el-select[name$='[target_count_unit]']"
    assert_select "[data-kinds='duration distance count interval'][data-hidden] input[name$='[work_seconds]'][disabled]", count: 1
    assert_select "[data-kinds='reps']:not([data-hidden]) input[name$='[tempo_cue]']:not([disabled])", count: 1

    ids = css_select("[id]").map { |node| node["id"] }
    assert_empty ids.tally.select { |_id, count| count > 1 }
  end

  test "an untouched required exercise renders the validation alert and blank choice" do
    sign_in_as users(:one)
    params = valid_template_params
    params[:workout_blocks_attributes]["0"][:exercise_prescriptions_attributes]["0"][:exercise_id] = ""

    assert_no_difference [ "WorkoutTemplate.count", "ExercisePrescription.count" ] do
      post workout_templates_path, params: { workout_template: params }
    end

    assert_response :unprocessable_entity
    assert_select "#workout-template-errors", text: /exercise must exist/i
    assert_select "select[name$='[exercise_id]'] option[value='']", text: "Choose exercise"
  end

  test "edit renders unique ids across live controls and inert templates" do
    sign_in_as users(:one)

    get edit_workout_template_path(workout_templates(:balanced))

    assert_response :success
    ids = css_select("[id]").map { |node| node["id"] }
    assert_empty ids.tally.select { |_id, count| count > 1 }
  end

  test "Turbo structural actions preserve the full three-level form without persistence" do
    sign_in_as users(:one)

    assert_no_difference [ "WorkoutTemplate.count", "WorkoutBlock.count", "ExercisePrescription.count" ] do
      post workout_templates_path,
        params: { workout_template: valid_template_params, add_prescription: "0" },
        headers: turbo_stream_headers
    end

    assert_response :success
    assert_select "turbo-stream[action='replace'][target='workout_template_form']"
    assert_select "select[name*='exercise_prescriptions_attributes'][name$='[exercise_id]']", count: 2
  end

  test "invalid structural coordinates fail safely with the complete form" do
    sign_in_as users(:one)

    post workout_templates_path,
      params: { workout_template: valid_template_params, remove_prescription: "0:99" },
      headers: turbo_stream_headers

    assert_response :unprocessable_entity
    assert_select "turbo-stream[action='replace'][target='workout_template_form']"
    assert_select "#workout-template-errors", text: /Invalid exercise prescription row/
  end

  test "structural coordinates still target the rendered block after a persisted removal" do
    sign_in_as users(:one)
    template = workout_templates(:balanced)
    params = persisted_template_params(template)

    patch workout_template_path(template),
      params: { workout_template: params, remove_block: "0" },
      headers: turbo_stream_headers

    assert_response :success
    params[:workout_blocks_attributes]["0"][:_destroy] = "1"

    patch workout_template_path(template),
      params: { workout_template: params, add_prescription: "1" },
      headers: turbo_stream_headers

    assert_response :success
    assert_select "section" do |sections|
      zone2 = sections.find { |section| section.css("input[value='Zone 2']").any? }
      assert_not_nil zone2
      assert_equal 2, zone2.css("select[name$='[exercise_id]']").size
      assert_equal 0, zone2.css("button[name='move_block']").size
      assert_equal [ "1:0:down", "1:1:up" ],
        zone2.css("button[name='move_prescription']").map { |button| button["value"] }.sort
    end
  end

  test "valid block moves remain wired while visible boundaries omit invalid actions" do
    sign_in_as users(:one)
    template = workout_templates(:balanced)

    patch workout_template_path(template),
      params: { workout_template: persisted_template_params(template), move_block: "1:up" },
      headers: turbo_stream_headers

    assert_response :success
    sections = css_select("section").select { |section| section.css("input[name$='[title]']").any? }
    assert_equal [ "Zone 2", "Strength" ],
      sections.map { |section| section.at_css("input[name$='[title]']")["value"] }
    assert_equal [ [ "Move down" ], [ "Move up" ] ],
      sections.map { |section| section.css("button[name='move_block']").map(&:text).map(&:strip) }
  end

  test "client supplied positions are normalized from one" do
    sign_in_as users(:one)
    params = valid_template_params.deep_merge(
      workout_blocks_attributes: {
        "0" => valid_template_params[:workout_blocks_attributes]["0"].merge(position: "0"),
        "1" => valid_template_params[:workout_blocks_attributes]["0"].merge(
          title: "Second",
          position: "0",
          exercise_prescriptions_attributes: {
            "0" => valid_template_params[:workout_blocks_attributes]["0"][:exercise_prescriptions_attributes]["0"]
          }
        )
      }
    )

    post workout_templates_path, params: { workout_template: params }

    assert_response :see_other
    assert_equal [ 1, 2 ], WorkoutTemplate.find_by!(title: "Test template").workout_blocks.pluck(:position)
  end

  test "show renders one thumbnail node per prescription and no empty image" do
    raster = create_catalog_exercise(name: "Raster thumb")
    add_image_visual(raster, filename: "frame-a.png", content_type: "image/png", alt_text: "PNG")
    raster.save!
    gif = create_catalog_exercise(name: "Gif thumb")
    add_image_visual(gif, filename: "animated.gif", content_type: "image/gif", alt_text: "GIF")
    gif.save!
    svg = create_catalog_exercise(name: "Svg thumb")
    add_image_visual(svg, filename: "icon.svg", content_type: "image/svg+xml", alt_text: "SVG")
    svg.save!
    video = create_catalog_exercise(name: "Video thumb")
    add_video_visual(video, alt_text: "Video")
    video.save!
    empty = create_catalog_exercise(name: "Empty thumb")
    template = create_workout_template_with([ raster, gif, svg, video, empty ], title: "Thumbnail types")

    sign_in_as users(:one)
    get workout_template_path(template)

    assert_response :success
    assert_select "[data-exercise-thumbnail]", count: 5
    assert_select "[data-exercise-thumbnail] img[src*='representations']", count: 1
    gif_proxy = rails_storage_proxy_path(gif.thumbnail_item.file)
    assert_select "[data-exercise-thumbnail] img[src='#{gif_proxy}']", count: 1
    assert_select "[data-exercise-thumbnail] svg", count: 3
    assert_select "img:not([src]), img[src='']", count: 0
  end

  test "show applies the dark thumbnail surface only to unmodified Workout Guide source art" do
    source = create_workout_guide_sequence_exercise(name: "Dark surface source")
    personal = create_catalog_exercise(name: "Dark surface personal")
    add_image_visual(personal, filename: "frame-a.png", content_type: "image/png", alt_text: "Personal")
    personal.save!
    modified = create_workout_guide_sequence_exercise(name: "Dark surface modified")
    modified.thumbnail_item.update!(source_identifier: "household-edit.png")
    template = create_workout_template_with([ source, personal, modified ], title: "Dark surface thumbs")

    sign_in_as users(:one)
    get workout_template_path(template)

    assert_response :success
    assert_select "[data-exercise-thumbnail].bg-gray-950", count: 1
    assert_select "[data-exercise-thumbnail]:not(.bg-gray-950)", count: 2
  end

  test "show forbids every transform for non-variant thumbnails" do
    gif = create_catalog_exercise(name: "Guard gif")
    add_image_visual(gif, filename: "animated.gif", content_type: "image/gif", alt_text: "GIF")
    gif.save!
    svg = create_catalog_exercise(name: "Guard svg")
    add_image_visual(svg, filename: "icon.svg", content_type: "image/svg+xml", alt_text: "SVG")
    svg.save!
    mp4 = create_catalog_exercise(name: "Guard mp4")
    add_video_visual(mp4, filename: "clip.mp4", content_type: "video/mp4", alt_text: "MP4")
    mp4.save!
    webm = create_catalog_exercise(name: "Guard webm")
    add_video_visual(webm, filename: "clip.webm", content_type: "video/webm", alt_text: "WEBM")
    webm.save!
    empty = create_catalog_exercise(name: "Guard empty")
    template = create_workout_template_with([ gif, svg, mp4, webm, empty ], title: "Forbidden transform thumbs")

    sign_in_as users(:one)
    with_forbidden_active_storage_transforms(:variant, :preview, :representation) do
      get workout_template_path(template)
    end
    assert_response :success
  end

  test "show forbids preview and representation for raster thumbnails and serves a usable variant" do
    png = create_catalog_exercise(name: "Usable png")
    add_image_visual(png, filename: "frame-a.png", content_type: "image/png", alt_text: "PNG")
    png.save!
    jpeg = create_catalog_exercise(name: "Usable jpeg")
    add_image_visual(jpeg, filename: "photo.jpg", content_type: "image/jpeg", alt_text: "JPEG")
    jpeg.save!
    webp = create_catalog_exercise(name: "Usable webp")
    add_image_visual(webp, filename: "photo.webp", content_type: "image/webp", alt_text: "WEBP")
    webp.save!
    template = create_workout_template_with([ png, jpeg, webp ], title: "Usable raster thumbs")

    sign_in_as users(:one)
    with_forbidden_active_storage_transforms(:preview, :representation) do
      get workout_template_path(template)
    end
    assert_response :success
    assert_select "[data-exercise-thumbnail] img[src*='representations']", count: 3

    css_select("[data-exercise-thumbnail] img").each do |image|
      get image["src"]
      follow_redirect! while response.redirect?
      assert_response :success
      assert_match %r{\Aimage/}, response.media_type
      assert response.body.present?
    end
  end

  test "show query count does not grow with rendered thumbnail count" do
    one = create_catalog_exercise(name: "Query one")
    add_image_visual(one, filename: "frame-a.png", content_type: "image/png", alt_text: "One")
    one.save!
    several = 4.times.map { |index|
      exercise = create_catalog_exercise(name: "Query several #{index}")
      add_image_visual(exercise, filename: "frame-a.png", content_type: "image/png", alt_text: "Several #{index}")
      exercise.save!
      exercise
    }
    one_template = create_workout_template_with([ one ], title: "Query one template")
    several_template = create_workout_template_with(several, title: "Query several template")

    sign_in_as users(:one)
    get workout_template_path(one_template)
    get workout_template_path(several_template)
    one_count = uncached_sql_count { get workout_template_path(one_template) }
    assert_select "[data-exercise-thumbnail]", count: 1
    several_count = uncached_sql_count { get workout_template_path(several_template) }
    assert_select "[data-exercise-thumbnail]", count: 4
    assert_equal one_count, several_count
  end

  private
    def valid_template_params
      {
        title: "Test template",
        description: "Structured template",
        provenance_status: "observed",
        source_name: "Test source",
        source_url: "https://example.com/test-template",
        workout_blocks_attributes: {
          "0" => {
            title: "Strength",
            block_kind: "strength",
            dose_class: "strength",
            planned_duration_minutes: "20",
            exercise_prescriptions_attributes: {
              "0" => {
                exercise_id: exercises(:squat).id,
                performance_kind: "reps",
                sets_count: "2",
                rep_min: "8",
                rep_max: "10",
                per_side: "1",
                tempo_cue: "3 sec lowering",
                target_heart_rate_min: "120",
                target_heart_rate_max: "150",
                target_heart_rate_unit: "bpm",
                dose_class: "strength"
              }
            }
          }
        }
      }
    end

    def turbo_stream_headers
      { "Accept" => Mime[:turbo_stream].to_s }
    end

    def persisted_template_params(template)
      {
        title: template.title,
        description: template.description,
        provenance_status: template.provenance_status,
        source_name: template.source_name,
        source_url: template.source_url,
        workout_blocks_attributes: template.workout_blocks.each_with_index.to_h do |block, block_index|
          [
            block_index.to_s,
            {
              id: block.id,
              title: block.title,
              block_kind: block.block_kind,
              dose_class: block.dose_class,
              planned_duration_minutes: block.planned_duration_minutes,
              exercise_prescriptions_attributes: block.exercise_prescriptions.each_with_index.to_h do |prescription, prescription_index|
                [
                  prescription_index.to_s,
                  {
                    id: prescription.id,
                    exercise_id: prescription.exercise_id,
                    performance_kind: prescription.performance_kind,
                    sets_count: prescription.sets_count,
                    rep_min: prescription.rep_min,
                    rep_max: prescription.rep_max,
                    work_seconds: prescription.work_seconds,
                    rest_seconds: prescription.rest_seconds,
                    dose_class: prescription.dose_class
                  }
                ]
              end
            }
          ]
        end
      }
    end
end
