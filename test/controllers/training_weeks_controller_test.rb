require "test_helper"

class TrainingWeeksControllerTest < ActionDispatch::IntegrationTest
  test "renders only Current person's in-progress sessions targets and progress" do
    sign_in_as users(:one)
    template = workout_templates(:balanced)

    get training_week_path, params: { date: "2026-07-29" }

    assert_response :success
    assert_select "h1", text: "Training"
    assert_select "h2", text: "In-progress workouts"
    assert_select "article", text: /Resume me/
    assert_select "article", text: /Sunday balanced day/
    assert_select "article", text: /Sam workout/, count: 0
    assert_select "a", text: "Resume workout"
    assert_select "form[action='#{weekly_dose_target_path}']"
    assert_select "section[aria-labelledby='templates-heading'] article" do
      assert_select "h3 + p",
        text: /Source: #{Regexp.escape(template.source_label)} · #{template.provenance_status.humanize}/
      assert_select "p.text-xs.uppercase", count: 0
    end
  end

  test "switching person removes the previous person's training HTML" do
    sign_in_as users(:one)
    patch person_context_path, params: { person_id: people(:two).id }

    get training_week_path, params: { date: "2026-07-29" }

    assert_response :success
    assert_select "article", text: /Sam workout/
    assert_select "article", text: /Resume me/, count: 0
    assert_select "article", text: /Sunday balanced day/, count: 0
  end
end
