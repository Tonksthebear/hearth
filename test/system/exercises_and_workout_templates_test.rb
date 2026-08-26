require "application_system_test_case"
require_relative "../test_helpers/exercise_visual_test_helper"
require_relative "../test_helpers/workout_guide_import_test_helper"

class ExercisesAndWorkoutTemplatesTest < ApplicationSystemTestCase
  include ExerciseVisualTestHelper
  include WorkoutGuideImportTestHelper

  test "creates a structured exercise and attributed workout template through the real UI" do
    sign_in_via_browser users(:one)

    click_link_and_wait_for_path "Activities", activity_week_path
    click_link_and_wait_for_path "Library", activity_library_path
    click_link_and_wait_for_path "All exercises", exercises_path, match: :first
    click_link_and_wait_for_path "Add exercise", new_exercise_path
    fill_in_and_wait_for_value "Name", "Farmer carry"
    select_and_wait "Strength", from: "Modality"
    select_and_wait "Carry", from: "Movement pattern"
    fill_in_and_wait_for_value "Equipment", "Kettlebells"
    fill_in_and_wait_for_value "Guidance", "Walk tall and brace."
    click_button_and_wait_for_text "Create Exercise", "Farmer carry"

    click_link_and_wait_for_path "Library", activity_library_path
    click_link_and_wait_for_path "All templates", workout_templates_path
    click_link_and_wait_for_path "Add workout template", new_workout_template_path
    fill_in_and_wait_for_value "Title", "Carry practice"
    select_and_wait "Personal", from: "Provenance"
    fill_in_and_wait_for_value "Block title", "Loaded carries"
    select_and_wait "Strength", from: "Block kind"
    select_and_wait "Strength", from: "Dose class"
    fill_in_and_wait_for_value "Planned minutes", "15"
    select_and_wait "Farmer carry", from: "Catalog exercise"
    select_and_wait "Reps", from: "Primary performance"
    fill_in_and_wait_for_value "Sets / rounds", "3"
    fill_in_and_wait_for_value "Minimum reps", "1"
    fill_in_and_wait_for_value "Maximum reps", "1"
    find("details summary", text: "Optional cues and targets").click
    fill_in_and_wait_for_value "Target RPE", "7"
    click_button_and_wait_for_text "Create Workout template", "Carry practice"

    assert_selector "h1", text: "Carry practice"
    assert_text "Farmer carry"
    assert_text "Personal"
    assert_text "not clinical endorsement"
    assert_text "medical advice"
  end

  test "switches native performance fields and preserves them through a full structural replacement" do
    sign_in_via_browser users(:one)
    visit_and_wait_for_path new_workout_template_path

    prescription = find("[data-controller='performance-fields']")
    kind = prescription.find("el-select[name$='[performance_kind]']")
    choose_elements_option kind, "Duration"
    within prescription do
      assert_field "Work duration (seconds)", wait: 5
      assert_no_field "Minimum reps"
      fill_in_and_wait_for_value "Work duration (seconds)", "45"
    end

    click_button_and_wait_for_count(
      "Add exercise prescription",
      "el-select[name$='[performance_kind]']",
      2
    )

    first_prescription = all("[data-controller='performance-fields']").first
    inactive_distance_units = all("[data-controller='performance-fields']")[1].all("el-select[name$='[target_distance_unit]']", visible: :all)
    assert inactive_distance_units.all?(&:disabled?)
    catalog_control = first_prescription.find("[data-elements-autocomplete]", visible: :all)
    within first_prescription do
      assert_field "Work duration (seconds)", with: "45", wait: 5
      assert_selector "el-selectedcontent", text: "Duration"
      choose_elements_option find("el-select[name$='[performance_kind]']"), "Distance"
      assert_field "Distance", wait: 5
      assert_field "Work duration (seconds)", with: "45"
      choose_elements_option find("el-select[name$='[target_distance_unit]']"), "m"
      assert_equal "m", find("el-select[name$='[target_distance_unit]']").value
      fill_in_and_wait_for_value "Distance", "400"
    end
    choose_elements_option catalog_control, "Stationary bike"

    fill_in_and_wait_for_value "Title", "Distance proof"
    all("button[name='remove_prescription']").last.click
    assert_selector "el-select[name$='[performance_kind]']", count: 1, wait: 5
    click_button_and_wait_for_text "Create Workout template", "Distance proof"

    prescription = WorkoutTemplate.find_by!(title: "Distance proof").workout_blocks.first.exercise_prescriptions.first
    assert_equal 45, prescription.work_seconds
    assert_equal 400, prescription.target_distance_amount
  end

  test "continues composing the intended block after removing a persisted sibling" do
    sign_in_via_browser users(:one)
    visit_and_wait_for_path edit_workout_template_path(workout_templates(:balanced))

    click_element_and_wait_for_count(
      all(:button, "Remove block").first,
      "#workout_template_form section.rounded-xl",
      1
    )

    within "#workout_template_form section.rounded-xl" do
      assert_field "Block title", with: "Zone 2"
      assert_no_button "Move up"
      assert_no_button "Move down"
      click_button_and_wait_for_count(
        "Add exercise prescription",
        "[data-elements-autocomplete] + .ss-main",
        2
      )
      assert_field "Block title", with: "Zone 2"
      assert_selector "button[name='move_prescription']", count: 2
    end
  end

  test "offers only valid block moves and performs the selected move" do
    sign_in_via_browser users(:one)
    visit_and_wait_for_path edit_workout_template_path(workout_templates(:balanced))

    blocks = all("#workout_template_form section.rounded-xl")
    within blocks.first do
      assert_field "Block title", with: "Strength"
      assert_no_button "Move up"
      assert_button "Move down"
    end
    within blocks[1] do
      assert_field "Block title", with: "Zone 2"
      assert_button "Move up"
      assert_no_button "Move down"
    end

    blocks.first.find_button("Move down").click
    assert_selector "#workout_template_form section.rounded-xl:nth-of-type(1) input[value='Zone 2']", wait: 5
    assert_no_selector "html[aria-busy='true']"

    blocks = all("#workout_template_form section.rounded-xl")
    within blocks.first do
      assert_field "Block title", with: "Zone 2"
      assert_no_button "Move up"
      assert_button "Move down"
    end
    within blocks[1] do
      assert_field "Block title", with: "Strength"
      assert_button "Move up"
      assert_no_button "Move down"
    end
  end

  test "keeps staged visual uploads through an invalid save and then persists frame order" do
    sign_in_via_browser users(:one)
    visit_and_wait_for_path new_exercise_path
    fill_in_and_wait_for_value "Name", exercises(:squat).name
    select_and_wait "Strength", from: "Modality"
    select_and_wait "Hinge", from: "Movement pattern"
    click_button_and_wait_for_count "Add visual", "input[type='file']", 1
    click_button_and_wait_for_count "Add file", "input[type='file']", 2
    select_and_wait "Frame sequence", from: "Kind"
    fill_in_and_wait_for_value "Accessible description", "Staged hinge"
    fill_in_and_wait_for_value "Frame interval (ms)", "1000"
    attach_file "File 1", file_fixture("exercises/frame-a.png")
    attach_file "File 2", file_fixture("exercises/frame-b.png")
    click_button "Create Exercise"
    assert_text "The exercise could not be saved", wait: 5

    signed_ids = all("input[type='hidden'][name$='[file]']", visible: :all).map { |field| field.value }
    assert_equal 2, signed_ids.size
    blobs = signed_ids.map { |signed_id| ActiveStorage::Blob.find_signed!(signed_id) }
    assert blobs.all? { |blob| blob.service.exist?(blob.key) }

    fill_in_and_wait_for_value "Name", "Staged sequence"
    click_button_and_wait_for_text "Create Exercise", "Staged sequence"
    frames = all("[data-frame-sequence-target='frame']", visible: :all)
    assert_equal 2, frames.size
    assert_includes frames.first[:src], blobs.first.filename.to_s
    assert_includes frames.last[:src], blobs.last.filename.to_s
  end

  test "advances a raster frame sequence by toggling data-hidden" do
    exercise = create_catalog_exercise(name: "Advancing sequence")
    add_frame_sequence(exercise, alt_text: "Advance", frame_interval_ms: 1000)
    exercise.save!

    sign_in_via_browser users(:one)
    visit_and_wait_for_path exercise_path(exercise)
    frames = all("[data-frame-sequence-target='frame']", visible: :all)
    assert_equal 2, frames.size
    initial_src = find("[data-frame-sequence-target='frame']:not([data-hidden])")[:src]
    assert page.has_no_selector?("[data-frame-sequence-target='frame']:not([data-hidden])[src='#{initial_src}']", wait: 3)
    assert_selector "[data-frame-sequence-target='frame']:not([data-hidden])", count: 1
  end

  test "renders mixed raster and svg frames without putting svg in an img" do
    exercise = create_catalog_exercise(name: "Mixed frames")
    add_frame_sequence(
      exercise,
      files: [ [ "frame-a.png", "image/png" ], [ "icon.svg", "image/svg+xml" ] ],
      alt_text: "Mixed frames"
    )
    exercise.save!
    svg_path = rails_storage_proxy_path(exercise.exercise_visuals.sole.download_items.sole.file)

    sign_in_via_browser users(:one)
    visit_and_wait_for_path exercise_path(exercise)
    assert_selector "a[href='#{svg_path}']"
    assert_no_selector "img[src='#{svg_path}']"
    assert_selector "[data-frame-sequence-target='frame']", visible: :all, count: 1
  end

  test "adds and saves a muscle target through the real browser form" do
    sign_in_via_browser users(:one)
    visit_and_wait_for_path new_exercise_path
    fill_in_and_wait_for_value "Name", "Targeted hinge"
    select_and_wait "Strength", from: "Modality"
    select_and_wait "Hinge", from: "Movement pattern"
    click_button_and_wait_for_count "Add muscle target", "el-select[name$='[muscle_id]']", 1
    assert_field "Name", with: "Targeted hinge"
    select_and_wait "Hamstrings", from: "Muscle"
    select_and_wait "Primary", from: "Role"
    click_button_and_wait_for_text "Create Exercise", "Targeted hinge"

    exercise = households(:home).exercises.find_by!(name: "Targeted hinge")
    target = exercise.exercise_muscle_targets.sole
    assert_equal muscles(:hamstrings), target.muscle
    assert_equal "primary", target.role
  end

  test "removes a persisted muscle target through the real browser form" do
    exercise = create_catalog_exercise(name: "Removable target")
    exercise.exercise_muscle_targets.create!(muscle: muscles(:glutes), role: :primary)
    exercise.save!

    sign_in_via_browser users(:one)
    visit_and_wait_for_path edit_exercise_path(exercise)
    click_button_and_wait_for_count "Remove muscle target", "el-select[name$='[muscle_id]']", 0
    click_button_and_wait_for_text "Update Exercise", "Removable target"

    assert_empty exercise.reload.exercise_muscle_targets
  end

  test "exposes native controls on a video visual" do
    exercise = create_catalog_exercise(name: "Video show")
    add_video_visual(exercise, alt_text: "Demo video")
    exercise.save!

    sign_in_via_browser users(:one)
    visit_and_wait_for_path exercise_path(exercise)
    assert_selector "video[controls][aria-label='Demo video']"
  end

  test "imports the workout guide from the exercises page and reads the broadcast summary" do
    sign_in_via_browser users(:one)
    visit_and_wait_for_path exercises_path

    with_fixture_workout_guide_import do
      click_button "Import Workout Guide"
      assert_text(/queued|running/i, wait: 5)
      assert_no_text "reclaim"
      perform_enqueued_jobs
      assert_text "Last import summary", wait: 10
      assert_text "Created"
    end
  end

  test "links an unlinked exercise and shows preserved household values" do
    sign_in_via_browser users(:one)
    visit_and_wait_for_path exercise_path(exercises(:squat))

    with_fixture_workout_guide_import do
      click_link "Link to catalog exercise"
      catalog_control = find("[data-elements-autocomplete]", visible: :all)
      choose_elements_option catalog_control, "Sumo Deadlift"
      click_button "Link to catalog exercise"
    end

    assert_text "Goblet squat", wait: 5
    assert_text "Preserved:"
    assert_text "name"
    assert_equal "workout_guide:sumo-deadlift", exercises(:squat).reload.source_key
    assert_equal "Goblet squat", exercises(:squat).name
  end

  test "replace from source asks for confirmation and uses the danger treatment" do
    fixture_workout_guide_import.run
    exercise = households(:home).exercises.find_by!(source_key: "workout_guide:bench-press")
    exercise.update!(equipment: "Household bar")

    sign_in_via_browser users(:one)
    visit_and_wait_for_path exercise_path(exercise)
    button = find(:button, "Replace from source")
    assert_includes button[:class], "text-danger-600"

    accept_confirm("Replace this exercise from the catalog? Household edits to source-owned fields will be overwritten.") do
      button.click
    end
    assert_text "Barbell", wait: 5
    assert_equal "Barbell", exercise.reload.equipment
  end
end

