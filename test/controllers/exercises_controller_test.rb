require "test_helper"
require_relative "../test_helpers/exercise_visual_test_helper"

class ExercisesControllerTest < ActionDispatch::IntegrationTest
  include ExerciseVisualTestHelper

  test "requires authentication" do
    get exercises_path
    assert_redirected_to new_session_path
  end

  test "renders and maintains the household exercise catalog" do
    sign_in_as users(:one)

    get exercises_path
    assert_response :success
    assert_select "h2", text: exercises(:squat).name

    assert_difference "Exercise.count", 1 do
      post exercises_path, params: {
        exercise: {
          name: "Farmer carry",
          modality: "strength",
          movement_pattern: "carry",
          equipment: "Kettlebells",
          guidance: "Walk tall."
        }
      }
    end

    exercise = households(:home).exercises.find_by!(name: "Farmer carry")
    assert_redirected_to exercise_path(exercise)

    patch exercise_path(exercise), params: { exercise: { guidance: "Brace and walk tall." } }
    assert_redirected_to exercise_path(exercise)
    assert_equal "Brace and walk tall.", exercise.reload.guidance
  end

  test "invalid submissions render the complete form" do
    sign_in_as users(:one)

    post exercises_path, params: { exercise: { name: "", modality: "", movement_pattern: "" } }

    assert_response :unprocessable_entity
    assert_select "form[action='#{exercises_path}']"
    assert_select "el-select[name='exercise[modality]']"
    assert_select "el-select[name='exercise[movement_pattern]']"
  end

  test "visuals fieldset exposes a direct-child legend" do
    sign_in_as users(:one)

    get new_exercise_path
    assert_response :success
    assert_select "fieldset > legend", text: "Visuals"
    assert_select "fieldset legend", text: "Visuals", count: 1

    get edit_exercise_path(exercises(:squat))
    assert_response :success
    assert_select "fieldset > legend", text: "Visuals"
    assert_select "fieldset legend", text: "Visuals", count: 1
  end

  test "does not render or load an exercise belonging to another household" do
    connection = ActiveRecord::Base.connection
    connection.execute("PRAGMA ignore_check_constraints = ON")
    other_household_id = Household.insert_all!([ {
      name: "Impossible second installation",
      installation_key: 2,
      created_at: Time.current,
      updated_at: Time.current
    } ], returning: %w[id]).rows.first.first
    other_exercise_id = Exercise.insert_all!([ {
      household_id: other_household_id,
      name: "Other household movement",
      modality: "strength",
      movement_pattern: "carry",
      created_at: Time.current,
      updated_at: Time.current
    } ], returning: %w[id]).rows.first.first
    connection.execute("PRAGMA ignore_check_constraints = OFF")
    sign_in_as users(:one)

    get exercises_path
    assert_response :success
    assert_select "h2", text: "Other household movement", count: 0

    get exercise_path(other_exercise_id)
    assert_response :not_found

    get new_workout_template_path
    assert_response :success
    assert_select "option[value='#{other_exercise_id}']", count: 0
  ensure
    connection&.execute("PRAGMA ignore_check_constraints = OFF")
  end

  test "creates an exercise with an image a frame sequence and a video" do
    sign_in_as users(:one)

    assert_difference("ExerciseVisual.count", 3) do
      post exercises_path, params: {
        exercise: valid_exercise_params.merge(
          name: "Visual catalog move",
          exercise_visuals_attributes: {
            "0" => image_visual_params.merge(
              caption: "Start position",
              display_attribution: "Household photo",
              source_key: "hinge-start",
              exercise_visual_items_attributes: {
                "0" => {
                  position: 1,
                  source_identifier: "catalog:hinge-start",
                  source_checksum: "source-checksum",
                  source_metadata: { "width" => "64" },
                  file: fixture_file_upload("exercises/frame-a.png", "image/png")
                }
              }
            ),
            "1" => {
              kind: "frame_sequence",
              position: 2,
              alt_text: "Hinge sequence",
              provenance_status: "personal",
              frame_interval_ms: 700,
              exercise_visual_items_attributes: {
                "0" => { position: 1, file: fixture_file_upload("exercises/frame-a.png", "image/png") },
                "1" => { position: 2, file: fixture_file_upload("exercises/frame-b.png", "image/png") }
              }
            },
            "2" => {
              kind: "video",
              position: 3,
              alt_text: "Hinge video",
              provenance_status: "personal",
              exercise_visual_items_attributes: {
                "0" => { position: 1, file: fixture_file_upload("exercises/clip.mp4", "video/mp4") }
              }
            }
          }
        )
      }
    end

    exercise = households(:home).exercises.find_by!(name: "Visual catalog move")
    assert_redirected_to exercise_path(exercise)
    visual = exercise.exercise_visuals.find_by!(source_key: "hinge-start")
    item = visual.exercise_visual_items.sole
    assert_equal "Start position", visual.caption
    assert_equal "Household photo", visual.display_attribution
    assert_equal "catalog:hinge-start", item.source_identifier
    assert_equal "source-checksum", item.source_checksum
    assert_equal({ "width" => "64" }, item.source_metadata)
  end

  test "invalid submissions preserve staged signed blob ids and create no visuals" do
    sign_in_as users(:one)

    assert_no_difference("ExerciseVisual.count") do
      post exercises_path, params: {
        exercise: valid_exercise_params.merge(
          name: "",
          exercise_visuals_attributes: {
            "0" => image_visual_params.merge(
              exercise_visual_items_attributes: {
                "0" => { position: 1, file: fixture_file_upload("exercises/frame-a.png", "image/png") }
              }
            )
          }
        )
      }
    end

    assert_response :unprocessable_entity
    signed_id = css_select("input[type='hidden'][name$='[file]']").sole["value"]
    blob = ActiveStorage::Blob.find_signed!(signed_id)
    assert blob.service.exist?(blob.key)

    post exercises_path, params: {
      exercise: valid_exercise_params.merge(
        name: "Recovered visual",
        exercise_visuals_attributes: {
          "0" => image_visual_params.merge(
            exercise_visual_items_attributes: {
              "0" => { position: 1, file: signed_id }
            }
          )
        }
      )
    }

    exercise = households(:home).exercises.find_by!(name: "Recovered visual")
    assert_redirected_to exercise_path(exercise)
    assert_equal blob, exercise.exercise_visuals.sole.exercise_visual_items.sole.file.blob
  end

  test "reorders persisted visuals and frames through PATCH" do
    sign_in_as users(:one)
    exercise = create_catalog_exercise(name: "Reorder through request")
    first = add_image_visual(exercise, alt_text: "First image")
    second = add_image_visual(exercise, alt_text: "Second image")
    sequence = add_frame_sequence(exercise, alt_text: "Ordered frames")
    exercise.save!
    frame_one, frame_two = sequence.exercise_visual_items.to_a

    patch exercise_path(exercise), params: {
      exercise: {
        name: exercise.name,
        modality: exercise.modality,
        movement_pattern: exercise.movement_pattern,
        exercise_visuals_attributes: {
          "0" => { id: first.id, position: 2, kind: "image", alt_text: first.alt_text, provenance_status: first.provenance_status },
          "1" => { id: second.id, position: 1, kind: "image", alt_text: second.alt_text, provenance_status: second.provenance_status },
          "2" => {
            id: sequence.id,
            position: 3,
            kind: "frame_sequence",
            alt_text: sequence.alt_text,
            provenance_status: sequence.provenance_status,
            frame_interval_ms: sequence.frame_interval_ms,
            exercise_visual_items_attributes: {
              "0" => { id: frame_one.id, position: 2 },
              "1" => { id: frame_two.id, position: 1 }
            }
          }
        }
      }
    }

    assert_redirected_to exercise_path(exercise)
    assert_equal [ second.id, first.id, sequence.id ], exercise.reload.exercise_visuals.map(&:id)
    assert_equal [ frame_two.id, frame_one.id ], sequence.reload.exercise_visual_items.map(&:id)
  end

  test "renders accessibility markup for each visual kind and hides source fields" do
    sign_in_as users(:one)
    exercise = create_catalog_exercise(name: "Accessible visuals")
    add_image_visual(exercise, alt_text: "Raster image", caption: "Start position", display_attribution: "Household photo")
    add_image_visual(exercise, filename: "icon.svg", content_type: "image/svg+xml", alt_text: "SVG image")
    add_frame_sequence(
      exercise,
      files: [ [ "frame-a.png", "image/png" ], [ "icon.svg", "image/svg+xml" ] ],
      alt_text: "Mixed sequence"
    )
    add_frame_sequence(
      exercise,
      files: [ [ "icon.svg", "image/svg+xml" ], [ "icon.svg", "image/svg+xml" ] ],
      alt_text: "SVG sequence"
    )
    add_video_visual(exercise, alt_text: "Demo video")
    exercise.save!

    get exercise_path(exercise)
    assert_response :success
    assert_select "img[alt='Raster image']"
    assert_select "video[controls][aria-label='Demo video']"
    assert_select "[role='img'][aria-label='Mixed sequence']"
    assert_select "[role='img'][aria-label='Mixed sequence'] img[alt='']"
    assert_select "a", text: "SVG image"
    assert_select "img[alt='SVG image']", count: 0
    svg_proxy = rails_storage_proxy_path(exercise.exercise_visuals.find_by!(alt_text: "Mixed sequence").download_items.sole.file)
    assert_select "a[href='#{svg_proxy}']"
    assert_select "img[src='#{svg_proxy}']", count: 0
    assert_select "[data-frame-sequence-target='frame'][src='#{svg_proxy}']", count: 0
    assert_select "[role='img'][aria-label='SVG sequence'] img", count: 0
    assert_select "figcaption", text: /Start position/
    assert_select "figcaption", text: /Household photo/
    assert_select "body", { text: /hinge-start|catalog:hinge-start|source-checksum/, count: 0 }
    assert_no_match %r{/rails/active_storage/representations/}, response.body
    assert_no_match %r{/rails/active_storage/previews/}, response.body
  end

  private
    def valid_exercise_params
      {
        name: "Catalog move",
        modality: "strength",
        movement_pattern: "hinge"
      }
    end

    def image_visual_params
      {
        kind: "image",
        position: 1,
        alt_text: "Image visual",
        provenance_status: "personal"
      }
    end
end
