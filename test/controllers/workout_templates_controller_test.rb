require "test_helper"

class WorkoutTemplatesControllerTest < ActionDispatch::IntegrationTest
  test "renders provenance source safety copy and a production start path" do
    sign_in_as users(:one)

    get workout_template_path(workout_templates(:balanced))

    assert_response :success
    assert_select "h1", text: workout_templates(:balanced).title
    assert_select "aside", text: /not clinical endorsement/i
    assert_select "aside", text: /medical advice/i
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
                entry_kind: "set",
                sets_count: "2",
                rep_min: "8",
                rep_max: "10",
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
end
