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
                    entry_kind: prescription.entry_kind,
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
