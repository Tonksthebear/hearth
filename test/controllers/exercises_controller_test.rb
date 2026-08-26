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
    assert_select "form[action='#{workout_guide_import_path}']"
    assert_select "button", text: "Import Workout Guide"

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

  test "creates a personal exercise with several muscle targets and roles" do
    sign_in_as users(:one)
    get new_exercise_path
    assert_response :success
    assert_select "fieldset > legend", text: "Muscle targets"

    assert_difference "Exercise.count", 1 do
      assert_difference "ExerciseMuscleTarget.count", 2 do
        post exercises_path, params: {
          exercise: valid_exercise_params.merge(
            name: "Household hinge",
            exercise_muscle_targets_attributes: {
              "0" => { muscle_id: muscles(:hamstrings).id, role: "primary" },
              "1" => { muscle_id: muscles(:glutes).id, role: "secondary" }
            }
          )
        }
      end
    end

    exercise = households(:home).exercises.find_by!(name: "Household hinge")
    assert_redirected_to exercise_path(exercise)
    assert_equal(
      [ [ "hamstrings", "primary" ], [ "glutes", "secondary" ] ].sort,
      exercise.exercise_muscle_targets.map { |target| [ target.muscle.key, target.role ] }.sort
    )
  end

  test "fully edits an imported exercise without changing source identity" do
    sign_in_as users(:one)
    exercise = create_imported_exercise
    original_key = exercise.source_key
    original_version = exercise.source_version

    get edit_exercise_path(exercise)
    assert_response :success
    assert_select "#exercise-source-heading", text: "Catalog source"
    assert_select "dd", text: "Workout Guide"
    assert_select "dd", text: "v1"
    assert_select "p", text: /no longer in the catalog/
    assert_select "body", { text: /catalog-hinge|source-checksum/, count: 0 }

    patch exercise_path(exercise), params: {
      exercise: {
        name: "Household hinge",
        modality: "mixed",
        movement_pattern: "hinge",
        guidance: "Brace the floor.",
        source_key: "attacker-key",
        source_version: "v9",
        exercise_muscle_targets_attributes: {
          "0" => { muscle_id: muscles(:hamstrings).id, role: "primary" }
        }
      }
    }

    assert_redirected_to exercise_path(exercise)
    exercise.reload
    assert_equal "Household hinge", exercise.name
    assert_equal "mixed", exercise.modality
    assert_equal "Brace the floor.", exercise.guidance
    assert_equal original_key, exercise.source_key
    assert_equal original_version, exercise.source_version
    assert_equal [ "hamstrings" ], exercise.exercise_muscle_targets.map { |target| target.muscle.key }
  end

  test "creates more than one custom frame sequence in one submission" do
    sign_in_as users(:one)
    get new_exercise_path
    assert_response :success

    assert_difference("ExerciseVisual.count", 2) do
      post exercises_path, params: {
        exercise: valid_exercise_params.merge(
          name: "Double sequence",
          exercise_visuals_attributes: {
            "0" => frame_sequence_visual_params(alt_text: "First sequence", position: 1),
            "1" => frame_sequence_visual_params(alt_text: "Second sequence", position: 2)
          }
        )
      }
    end

    exercise = households(:home).exercises.find_by!(name: "Double sequence")
    assert_redirected_to exercise_path(exercise)
    assert_equal [ "First sequence", "Second sequence" ], exercise.exercise_visuals.order(:position).map(&:alt_text)
    assert exercise.exercise_visuals.all? { |visual| visual.exercise_visual_items.size == 2 }
  end

  test "add and remove muscle target over Turbo Stream preserve typed fields and staged files" do
    sign_in_as users(:one)
    get new_exercise_path
    assert_response :success

    post exercises_path, params: staged_visual_params.merge(
      exercise: staged_visual_params[:exercise].merge(name: "Typed hinge"),
      add_muscle_target: "1"
    ), headers: turbo_stream_headers

    assert_response :success
    assert_equal Mime[:turbo_stream], response.media_type
    assert_select "turbo-stream[action='replace'][target='exercise_form']"
    assert_select "input[name='exercise[name]'][value='Typed hinge']"
    assert_select "el-select[name$='[muscle_id]']", count: 1
    signed_id = css_select("input[type='hidden'][name$='[file]']").sole["value"]
    assert ActiveStorage::Blob.find_signed!(signed_id)

    post exercises_path, params: {
      exercise: staged_visual_params[:exercise].merge(
        name: "Typed hinge",
        exercise_visuals_attributes: {
          "0" => image_visual_params.merge(
            exercise_visual_items_attributes: {
              "0" => { position: 1, file: signed_id }
            }
          )
        },
        exercise_muscle_targets_attributes: {
          "0" => { muscle_id: muscles(:hamstrings).id, role: "primary" }
        }
      ),
      remove_muscle_target: "0"
    }, headers: turbo_stream_headers

    assert_response :success
    assert_equal Mime[:turbo_stream], response.media_type
    assert_select "input[name='exercise[name]'][value='Typed hinge']"
    assert_select "el-select[name$='[muscle_id]']", count: 0
    assert_equal signed_id, css_select("input[type='hidden'][name$='[file]']").sole["value"]
  end

  test "visual structural actions still preserve staged signed blob ids" do
    sign_in_as users(:one)
    get new_exercise_path
    assert_select "fieldset > legend", text: "Muscle targets"

    post exercises_path, params: staged_visual_params.merge(add_visual: "1"), headers: turbo_stream_headers
    assert_response :success
    first_signed_id = css_select("input[type='hidden'][name$='[file]']").sole["value"]
    assert ActiveStorage::Blob.find_signed!(first_signed_id)

    post exercises_path, params: {
      exercise: valid_exercise_params.merge(
        exercise_visuals_attributes: {
          "0" => image_visual_params.merge(
            exercise_visual_items_attributes: { "0" => { position: 1, file: first_signed_id } }
          ),
          "1" => { kind: "image", position: 2, alt_text: "Blank visual", provenance_status: "personal" }
        }
      ),
      remove_visual: "1"
    }, headers: turbo_stream_headers
    assert_response :success
    assert_equal first_signed_id, css_select("input[type='hidden'][name$='[file]']").sole["value"]

    post exercises_path, params: {
      exercise: valid_exercise_params.merge(
        exercise_visuals_attributes: {
          "0" => image_visual_params.merge(
            exercise_visual_items_attributes: { "0" => { position: 1, file: first_signed_id } }
          )
        }
      ),
      add_visual_item: "0"
    }, headers: turbo_stream_headers
    assert_response :success
    assert_equal first_signed_id, css_select("input[type='hidden'][name$='[file]']").sole["value"]
    assert_select "input[type='file'][name$='[file]']", count: 2

    post exercises_path, params: {
      exercise: valid_exercise_params.merge(
        exercise_visuals_attributes: {
          "0" => image_visual_params.merge(
            kind: "frame_sequence",
            alt_text: "Staged sequence",
            frame_interval_ms: 700,
            exercise_visual_items_attributes: {
              "0" => { position: 1, file: first_signed_id },
              "1" => { position: 2, file: fixture_file_upload("exercises/frame-b.png", "image/png") }
            }
          )
        }
      ),
      remove_visual_item: "0:1"
    }, headers: turbo_stream_headers
    assert_response :success
    assert_equal first_signed_id, css_select("input[type='hidden'][name$='[file]']").first["value"]
  end

  test "structural add and remove with Accept text/html return a usable HTML form" do
    sign_in_as users(:one)
    get new_exercise_path
    assert_response :success

    post exercises_path, params: {
      exercise: valid_exercise_params.merge(name: "HTML hinge"),
      add_muscle_target: "1"
    }, headers: html_headers

    assert_response :success
    assert_equal "text/html", response.media_type
    assert_select "form[action='#{exercises_path}']"
    assert_select "input[name='exercise[name]'][value='HTML hinge']"
    assert_select "el-select[name='exercise[exercise_muscle_targets_attributes][0][muscle_id]']"
    assert_select "el-select[name='exercise[exercise_muscle_targets_attributes][0][role]']"

    exercise = create_imported_exercise
    get edit_exercise_path(exercise)
    assert_response :success

    patch exercise_path(exercise), params: {
      exercise: {
        name: exercise.name,
        modality: exercise.modality,
        movement_pattern: exercise.movement_pattern,
        exercise_muscle_targets_attributes: {
          "0" => { muscle_id: muscles(:glutes).id, role: "primary" }
        }
      },
      remove_muscle_target: "0"
    }, headers: html_headers

    assert_response :success
    assert_equal "text/html", response.media_type
    assert_select "form[action='#{exercise_path(exercise)}']"
    assert_select "el-select[name$='[muscle_id]']", count: 0
  end

  test "duplicate muscle rows re-render a named error on create and update" do
    sign_in_as users(:one)
    get new_exercise_path
    assert_response :success

    assert_no_difference [ "Exercise.count", "ExerciseMuscleTarget.count" ] do
      post exercises_path, params: {
        exercise: valid_exercise_params.merge(
          name: "Duplicate create",
          exercise_muscle_targets_attributes: {
            "0" => { muscle_id: muscles(:quadriceps).id, role: "primary" },
            "1" => { muscle_id: muscles(:quadriceps).id, role: "secondary" }
          }
        )
      }
    end

    assert_response :unprocessable_entity
    assert_select "li", text: "Quadriceps is assigned more than once"

    exercise = create_catalog_exercise(name: "Duplicate update")
    get edit_exercise_path(exercise)
    assert_response :success

    assert_no_difference "ExerciseMuscleTarget.count" do
      patch exercise_path(exercise), params: {
        exercise: {
          name: exercise.name,
          modality: exercise.modality,
          movement_pattern: exercise.movement_pattern,
          exercise_muscle_targets_attributes: {
            "0" => { muscle_id: muscles(:quadriceps).id, role: "primary" },
            "1" => { muscle_id: muscles(:quadriceps).id, role: "secondary" }
          }
        }
      }
    end

    assert_response :unprocessable_entity
    assert_select "li", text: "Quadriceps is assigned more than once"
  end

  test "a blank muscle re-renders a visible error" do
    sign_in_as users(:one)
    get new_exercise_path
    assert_response :success

    post exercises_path, params: {
      exercise: valid_exercise_params.merge(
        name: "Blank muscle",
        exercise_muscle_targets_attributes: {
          "0" => { muscle_id: "", role: "primary" }
        }
      )
    }

    assert_response :unprocessable_entity
    assert_select "form[action='#{exercises_path}']"
    assert_match(/muscle/i, response.body)
  end

  test "uploads a still image an animated gif and a video" do
    sign_in_as users(:one)
    get new_exercise_path
    assert_response :success

    assert_difference("ExerciseVisual.count", 3) do
      post exercises_path, params: {
        exercise: valid_exercise_params.merge(
          name: "Upload kinds",
          exercise_visuals_attributes: {
            "0" => image_visual_params.merge(
              alt_text: "Still image",
              exercise_visual_items_attributes: {
                "0" => { position: 1, file: fixture_file_upload("exercises/frame-a.png", "image/png") }
              }
            ),
            "1" => image_visual_params.merge(
              position: 2,
              alt_text: "Animated gif",
              exercise_visual_items_attributes: {
                "0" => { position: 1, file: fixture_file_upload("exercises/animated.gif", "image/gif") }
              }
            ),
            "2" => {
              kind: "video",
              position: 3,
              alt_text: "Demo video",
              provenance_status: "personal",
              exercise_visual_items_attributes: {
                "0" => { position: 1, file: fixture_file_upload("exercises/clip.mp4", "video/mp4") }
              }
            }
          }
        )
      }
    end

    exercise = households(:home).exercises.find_by!(name: "Upload kinds")
    assert_redirected_to exercise_path(exercise)
    types = exercise.exercise_visuals.order(:position).flat_map { |visual|
      visual.exercise_visual_items.map { |item| item.file.content_type }
    }
    assert_equal [ "image/png", "image/gif", "video/mp4" ], types
  end

  test "a plain PATCH with edited numeric positions reorders and renormalizes to 1" do
    sign_in_as users(:one)
    exercise = create_catalog_exercise(name: "Visible positions")
    first = add_image_visual(exercise, alt_text: "First image")
    second = add_image_visual(exercise, alt_text: "Second image")
    exercise.save!

    get edit_exercise_path(exercise)
    assert_response :success
    assert_select "input[type='number'][name$='[position]'][min='1']"

    patch exercise_path(exercise), params: {
      exercise: {
        name: exercise.name,
        modality: exercise.modality,
        movement_pattern: exercise.movement_pattern,
        exercise_visuals_attributes: {
          "0" => { id: first.id, position: 5, kind: "image", alt_text: first.alt_text, provenance_status: first.provenance_status },
          "1" => { id: second.id, position: 2, kind: "image", alt_text: second.alt_text, provenance_status: second.provenance_status }
        }
      }
    }

    assert_redirected_to exercise_path(exercise)
    assert_equal [ second.id, first.id ], exercise.reload.exercise_visuals.map(&:id)
    assert_equal [ 1, 2 ], exercise.exercise_visuals.map(&:position)
  end

  test "a duplicate-position PATCH resolves without a uniqueness error" do
    sign_in_as users(:one)
    exercise = create_catalog_exercise(name: "Duplicate positions")
    first = add_image_visual(exercise, alt_text: "First image")
    second = add_image_visual(exercise, alt_text: "Second image")
    exercise.save!

    get edit_exercise_path(exercise)
    assert_response :success

    patch exercise_path(exercise), params: {
      exercise: {
        name: exercise.name,
        modality: exercise.modality,
        movement_pattern: exercise.movement_pattern,
        exercise_visuals_attributes: {
          "0" => { id: first.id, position: 1, kind: "image", alt_text: first.alt_text, provenance_status: first.provenance_status },
          "1" => { id: second.id, position: 1, kind: "image", alt_text: second.alt_text, provenance_status: second.provenance_status }
        }
      }
    }

    assert_redirected_to exercise_path(exercise)
    assert_equal [ 1, 2 ], exercise.reload.exercise_visuals.map(&:position)
    assert_equal [ first.id, second.id ].sort, exercise.exercise_visuals.map(&:id).sort
  end

  test "does not render another household exercise for edit" do
    connection = ActiveRecord::Base.connection
    connection.execute("PRAGMA ignore_check_constraints = ON")
    other_household_id = Household.insert_all!([ {
      name: "Foreign install",
      installation_key: 3,
      created_at: Time.current,
      updated_at: Time.current
    } ], returning: %w[id]).rows.first.first
    other_exercise_id = Exercise.insert_all!([ {
      household_id: other_household_id,
      name: "Foreign movement",
      modality: "strength",
      movement_pattern: "carry",
      created_at: Time.current,
      updated_at: Time.current
    } ], returning: %w[id]).rows.first.first
    connection.execute("PRAGMA ignore_check_constraints = OFF")
    sign_in_as users(:one)

    get edit_exercise_path(other_exercise_id)
    assert_response :not_found
  ensure
    connection&.execute("PRAGMA ignore_check_constraints = OFF")
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

    def frame_sequence_visual_params(alt_text:, position:)
      {
        kind: "frame_sequence",
        position: position,
        alt_text: alt_text,
        provenance_status: "personal",
        frame_interval_ms: 700,
        exercise_visual_items_attributes: {
          "0" => { position: 1, file: fixture_file_upload("exercises/frame-a.png", "image/png") },
          "1" => { position: 2, file: fixture_file_upload("exercises/frame-b.png", "image/png") }
        }
      }
    end

    def staged_visual_params
      {
        exercise: valid_exercise_params.merge(
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

    def create_imported_exercise
      households(:home).exercises.create!(
        name: "Imported hinge",
        modality: "strength",
        movement_pattern: "hinge",
        source_key: "catalog-hinge",
        source_version: "v1",
        source_removed_at: Time.current,
        source_snapshot: {
          "attribution" => {
            "source_name" => "Workout Guide",
            "creator" => "Workout Guide",
            "license" => "CC BY-SA 4.0",
            "change_note" => "Initial catalog import"
          }
        }
      )
    end

    def turbo_stream_headers
      { "Accept" => Mime[:turbo_stream].to_s }
    end

    def html_headers
      { "Accept" => "text/html" }
    end
end
