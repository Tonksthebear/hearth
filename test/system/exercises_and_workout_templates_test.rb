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
    select_and_wait "Set", from: "Entry kind"
    fill_in_and_wait_for_value "Sets / rounds", "3"
    fill_in_and_wait_for_value "Min reps", "1"
    fill_in_and_wait_for_value "Max reps", "1"
    fill_in_and_wait_for_value "Target RPE", "7"
    click_button_and_wait_for_text "Create Workout template", "Carry practice"

    assert_selector "h1", text: "Carry practice"
    assert_text "Farmer carry"
    assert_text "Personal"
    assert_text "not clinical endorsement"
    assert_text "medical advice"
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
