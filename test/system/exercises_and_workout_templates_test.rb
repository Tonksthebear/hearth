require "application_system_test_case"

class ExercisesAndWorkoutTemplatesTest < ApplicationSystemTestCase
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
      assert_field "Target duration (seconds)", wait: 5
      assert_no_field "Minimum reps"
      fill_in_and_wait_for_value "Target duration (seconds)", "45"
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
      assert_field "Target duration (seconds)", with: "45", wait: 5
      assert_selector "el-selectedcontent", text: "Duration"
      choose_elements_option find("el-select[name$='[performance_kind]']"), "Distance"
      assert_field "Target distance", wait: 5
      assert_no_field "Target duration (seconds)"
      choose_elements_option find("el-select[name$='[target_distance_unit]']"), "m"
      assert_equal "m", find("el-select[name$='[target_distance_unit]']").value
      fill_in_and_wait_for_value "Target distance", "400"
    end
    choose_elements_option catalog_control, "Stationary bike"

    fill_in_and_wait_for_value "Title", "Distance proof"
    all("button[name='remove_prescription']").last.click
    assert_selector "el-select[name$='[performance_kind]']", count: 1, wait: 5
    click_button_and_wait_for_text "Create Workout template", "Distance proof"

    prescription = WorkoutTemplate.find_by!(title: "Distance proof").workout_blocks.first.exercise_prescriptions.first
    assert_nil prescription.work_seconds
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
end
