require "application_system_test_case"

class TrainingSessionsTest < ApplicationSystemTestCase
  WEEK_START = Date.new(2026, 7, 27)

  test "requires confirmation before deleting a workout draft" do
    training_session = training_sessions(:draft)
    sign_in_via_browser users(:one)
    visit_and_wait_for_path training_session_path(training_session)

    dismiss_confirm("Delete this workout draft?") { click_button "Delete draft" }
    assert TrainingSession.exists?(training_session.id)
    assert_current_path training_session_path(training_session)

    accept_confirm("Delete this workout draft?") { click_button "Delete draft" }
    assert_current_path training_week_path(date: training_session.performed_on), wait: 5
    assert_not TrainingSession.exists?(training_session.id)
  end

  test "starts a template snapshot records actual rows completes and updates progress" do
    travel_to WEEK_START do
      sign_in_via_browser users(:one)
      click_link_and_wait_for_path "Activities", activity_overview_path
      click_link_and_wait_for_path "Templates", workout_templates_path
      click_link_and_wait_for_path workout_templates(:balanced).title, workout_template_path(workout_templates(:balanced))
      click_button_and_wait_for_text "Start workout", "Record Balanced training day"

      reps = all("input[name*='training_sets_attributes'][name$='[reps]']")
      loads = all("input[name*='training_sets_attributes'][name$='[load_amount]']")
      load_units = all("el-select[name*='training_sets_attributes'][name$='[load_unit]']")
      durations = all("input[name*='training_sets_attributes'][name$='[duration_seconds]']")
      completed = all("input[type='checkbox'][name*='training_sets_attributes'][name$='[completed]']")

      set_and_wait reps[0], "8"
      set_and_wait reps[1], "8"
      set_and_wait loads[0], "35"
      set_and_wait loads[1], "35"
      choose_elements_option load_units[0], "lb"
      choose_elements_option load_units[1], "lb"
      set_and_wait durations[2], "1800"
      completed.each { |field| check_and_wait field }

      click_button_and_wait_for_text "Complete workout", "Workout completed."
      assert_text(/completed workout/i)
      assert_text "Goblet squat"
      assert_text "Stationary bike"

      click_link_and_wait_for_path "Training", training_week_path, match: :first
      assert_selector "article", text: /Structured minutes\s+100 min/
      assert_selector "article", text: /Strength sessions\s+2 sessions/
    end
  end

  test "saves resumes and completes a structured inline ad hoc workout without catalog mutation" do
    travel_to WEEK_START do
      exercise_count = Exercise.count
      sign_in_via_browser users(:one)
      click_link_and_wait_for_path "Activities", activity_overview_path
      click_link_and_wait_for_path "Training", training_week_path, match: :first
      click_link_and_wait_for_path "Log ad hoc workout", new_training_session_path

      assert_field "Workout title", with: "Ad hoc workout", wait: 5
      fill_in "Workout title", with: "Neighborhood walk"
      assert_field "Workout title", with: "Neighborhood walk"
      fill_in_and_wait_for_value "Block title", "Outdoor walk"
      select_and_wait "Zone2", from: "Block kind"
      select_and_wait "Zone2", from: "Block dose"
      fill_in_and_wait_for_value "Actual duration (seconds)", "1800"
      fill_in_and_wait_for_value "Exercise name", "Neighborhood walk"
      select_and_wait "Cardio", from: "Modality"
      select_and_wait "Locomotion cardio", from: "Movement pattern"
      exercise_entry_kind = all("el-select[name*='training_session_exercises_attributes'][name$='[snapshot_entry_kind]']").first
      choose_elements_option exercise_entry_kind, "Interval"
      select_and_wait "Zone2", from: "Default dose"
      select_and_wait "Interval", from: all("el-select[name*='training_sets_attributes'][name$='[entry_kind]']").first[:id]
      select_and_wait "Zone2", from: all("el-select[name*='training_sets_attributes'][name$='[dose_class]']").first[:id]
      set_and_wait all("input[name*='training_sets_attributes'][name$='[duration_seconds]']").first, "1800"
      check_and_wait all("input[type='checkbox'][name*='training_sets_attributes'][name$='[completed]']").first
      click_button_and_wait_for_text "Save draft", "Workout draft saved."

      click_link_and_wait_for_path "Training", training_week_path, match: :first
      assert_selector "article", text: /Neighborhood walk.*excluded from progress until completed/m
      session = TrainingSession.find_by!(snapshot_title: "Neighborhood walk")
      within find("article", text: /Neighborhood walk/) do
        click_link "Resume workout"
      end
      assert_current_path edit_training_session_path(session)
      click_button_and_wait_for_text "Complete workout", "Workout completed."

      assert_equal exercise_count, Exercise.count
      assert_text "Neighborhood walk"
      assert_text(/completed workout/i)
    end
  end

  test "switching people removes prior person training and targets from rendered HTML" do
    travel_to WEEK_START do
      people(:one).update!(weekly_structured_minutes_target: 123)
      people(:two).update!(weekly_structured_minutes_target: 45)
      sign_in_via_browser users(:one)

      click_link_and_wait_for_path "Activities", activity_overview_path
      click_link_and_wait_for_path "Training", training_week_path, match: :first
      assert_text "Resume me"
      assert_field "Structured minutes", with: "123"

      switch_person_via_browser people(:two)
      click_link_and_wait_for_path "Activities", activity_overview_path
      click_link_and_wait_for_path "Training", training_week_path, match: :first
      assert_no_text "Resume me"
      assert_no_text "Sunday balanced day"
      assert_text "Sam workout"
      assert_field "Structured minutes", with: "45"
      assert_no_field "Structured minutes", with: "123"
    end
  end
end
