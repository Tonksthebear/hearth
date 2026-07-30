require "application_system_test_case"

class RecoveryHabitsTest < ApplicationSystemTestCase
  test "defines configures records corrects and isolates recovery habits on mobile" do
    page.driver.browser.execute_cdp(
      "Emulation.setDeviceMetricsOverride",
      width: 390,
      height: 900,
      deviceScaleFactor: 1,
      mobile: false
    )

    sign_in_via_browser users(:one)
    assert_equal 390, page.evaluate_script("window.innerWidth")
    click_link_and_wait_for_path "Recovery", recovery_day_path

    click_link_and_wait_for_path "Manage habits", habits_path
    click_link_and_wait_for_path "New habit", new_habit_path

    fill_in_and_wait_for_value "Name", "Evening reset"
    fill_in_and_wait_for_value "Description", "A personal wind-down check."
    fill_metric(0, key: "duration", label: "Duration", type: "Duration", unit: "minutes")

    click_button_and_wait_for_count "Add metric", "input[name$='[key]']", 2
    fill_metric(1, key: "temperature", label: "Temperature", type: "Number", unit: "°F")

    page.execute_script("arguments[0].click()", first("button[name='move_metric'][value='0:down']"))
    assert_field "habit_habit_metrics_attributes_0_key", with: "temperature", wait: 5
    assert_equal %w[temperature duration], all("input[name$='[key]']").map(&:value)

    click_button_and_wait_for_path "Create Habit", habits_path
    within find("article", text: "Evening reset") do
      click_button "Activate for Alex"
    end
    activated_habit = Habit.find_by!(name: "Evening reset")
    assert_text "Configure Evening reset", wait: 5
    configuration = people(:one).person_habits.find_by!(habit: activated_habit)
    assert_current_path edit_person_habit_path(configuration), wait: 5

    fill_in_and_wait_for_value "Temperature target", "168"
    fill_in_and_wait_for_value "Duration target", "20"
    click_button_and_wait_for_path "Save configuration", recovery_day_path

    within "#today-person-habit-#{configuration.id}" do
      assert_text "Your target: 168.0 °F"
      fill_in_and_wait_for_value "Temperature", "165"
      fill_in_and_wait_for_value "Duration", "18"
      click_button "Record today's check-in"
    end
    assert_current_path recovery_day_path
    assert_text "165.0 °F"
    assert_text "18 minutes"

    within "#today-person-habit-#{configuration.id}" do
      fill_in_and_wait_for_value "Temperature", "170"
      fill_in_and_wait_for_value "Duration", "22"
      click_button "Correct today's check-in"
    end
    assert_current_path recovery_day_path
    assert_text "170.0 °F"
    assert_text "22 minutes"

    within "#today-person-habit-#{person_habits(:alex_water).id}" do
      click_button "Clear"
    end
    assert_current_path recovery_day_path
    within "#today-person-habit-#{person_habits(:alex_water).id}" do
      click_button "Check off"
    end
    assert_current_path recovery_day_path
    within "#today-person-habit-#{person_habits(:alex_water).id}" do
      assert_text "Checked"
    end

    within "#today-person-habit-#{configuration.id}" do
      click_link "Configure"
    end
    assert_current_path edit_person_habit_path(configuration)
    click_button_and_wait_for_path "Deactivate habit", recovery_day_path
    assert_no_selector "#today-person-habit-#{configuration.id}"
    assert_selector "article", text: /Evening reset.*History only/im

    switch_person_via_browser people(:two)
    click_link_and_wait_for_path "Recovery", recovery_day_path
    assert_no_text "Evening reset"
    assert_no_text "170.0 °F"
    assert_no_text "Your target: 20 minutes"
  ensure
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end

  private
    def fill_metric(index, key:, label:, type:, unit:)
      section = all("section").select { |candidate| candidate.has_css?("input[name$='[key]']") }.fetch(index)
      within section do
        set_and_wait find("input[name$='[key]']"), key
        set_and_wait find("input[name$='[label]']"), label
        select_and_wait type, from: find("el-select[name$='[value_type]']")[:id]
        set_and_wait find("input[name$='[unit]']"), unit
      end
    end
end
