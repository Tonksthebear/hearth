require "test_helper"

class TrainingSessionsControllerTest < ActionDispatch::IntegrationTest
  test "starts a template snapshot draft for Current person" do
    sign_in_as users(:one)

    assert_difference "TrainingSession.count", 1 do
      post training_sessions_path, params: { template_id: workout_templates(:balanced).id }
    end

    session = people(:one).training_sessions.order(:created_at).last
    assert_redirected_to edit_training_session_path(session)
    assert_equal "Balanced training day", session.snapshot_title
    assert_equal 2, session.training_session_blocks.size
  end

  test "creates a structured inline ad hoc draft without changing the catalog" do
    sign_in_as users(:one)

    assert_difference "TrainingSession.count", 1 do
      assert_no_difference "Exercise.count" do
        post training_sessions_path, params: { training_session: ad_hoc_params }
      end
    end

    session = people(:one).training_sessions.order(:created_at).last
    assert_redirected_to edit_training_session_path(session)
    assert_nil session.training_session_blocks.first.training_session_exercises.first.exercise_id
  end

  test "Turbo structural actions replace the complete draft form without persisting" do
    sign_in_as users(:one)

    assert_no_difference [ "TrainingSession.count", "TrainingSessionBlock.count", "TrainingSet.count" ] do
      post training_sessions_path,
        params: { training_session: ad_hoc_params, add_training_set: "0:0" },
        headers: turbo_stream_headers
    end

    assert_response :success
    assert_select "turbo-stream[action='replace'][target='training_session_form']"
    assert_select "input[name*='training_sets_attributes'][name$='[reps]']", count: 2
  end

  test "completes a saved draft and then makes it read only" do
    sign_in_as users(:one)
    session = training_sessions(:draft)

    patch training_session_path(session), params: {
      complete: "1",
      training_session: persisted_draft_params(session)
    }

    assert_redirected_to training_session_path(session)
    assert_predicate session.reload, :completed?

    patch training_session_path(session), params: {
      training_session: persisted_draft_params(session).merge(snapshot_title: "Forged change")
    }
    assert_redirected_to training_session_path(session)
    assert_equal "Resume me", session.reload.snapshot_title
  end

  test "invalid completion rerenders every structured row with model errors" do
    sign_in_as users(:one)
    session = training_sessions(:draft)
    params = persisted_draft_params(session)
    params[:training_session_blocks_attributes]["0"][:actual_duration_seconds] = ""
    params[:training_session_blocks_attributes]["0"][:training_session_exercises_attributes]["0"][:training_sets_attributes]["0"][:completed] = "0"

    patch training_session_path(session), params: { complete: "1", training_session: params }

    assert_response :unprocessable_entity
    assert_select "#training-session-errors", text: /requires an actual duration/
    assert_select "input[name*='training_session_blocks_attributes'][name$='[id]'][value='#{session.training_session_blocks.first.id}']"
    assert_select "input[name*='training_sets_attributes'][name$='[id]']"
  end

  test "structural coordinates still target the rendered block after a persisted removal" do
    sign_in_as users(:one)
    session = training_sessions(:draft)
    second_block = session.training_session_blocks.create!(
      position: 2,
      snapshot_title: "Second block",
      snapshot_block_kind: :other,
      snapshot_dose_class: :none
    )
    second_exercise = second_block.training_session_exercises.create!(
      position: 1,
      snapshot_name: "Walk",
      snapshot_modality: :cardio,
      snapshot_movement_pattern: :locomotion_cardio,
      snapshot_entry_kind: :interval,
      snapshot_dose_class: :none
    )
    second_exercise.training_sets.create!(position: 1, entry_kind: :interval, dose_class: :none)
    params = persisted_session_params(session.reload)

    patch training_session_path(session),
      params: { training_session: params, remove_session_block: "0" },
      headers: turbo_stream_headers

    assert_response :success
    params[:training_session_blocks_attributes]["0"][:_destroy] = "1"

    patch training_session_path(session),
      params: { training_session: params, add_session_exercise: "1" },
      headers: turbo_stream_headers

    assert_response :success
    assert_select "section" do |sections|
      second = sections.find { |section| section.css("input[value='Second block']").any? }
      assert_not_nil second
      assert_equal 2, second.css("input[name$='[snapshot_name]']").size
    end
  end

  test "another person's sessions are not visible or mutable" do
    sign_in_as users(:one)

    get training_session_path(training_sessions(:other_person))
    assert_response :not_found

    patch training_session_path(training_sessions(:other_person)), params: {
      training_session: { snapshot_title: "Forged" }
    }
    assert_response :not_found
  end

  private
    def ad_hoc_params
      {
        snapshot_title: "Outdoor walk",
        performed_on: "2026-07-31",
        notes: "Easy walk",
        training_session_blocks_attributes: {
          "0" => {
            snapshot_title: "Walk",
            snapshot_block_kind: "zone2",
            snapshot_dose_class: "zone2",
            actual_duration_seconds: "1800",
            training_session_exercises_attributes: {
              "0" => {
                exercise_id: "",
                snapshot_name: "Outdoor walk",
                snapshot_modality: "cardio",
                snapshot_movement_pattern: "locomotion_cardio",
                snapshot_entry_kind: "interval",
                snapshot_dose_class: "zone2",
                training_sets_attributes: {
                  "0" => {
                    entry_kind: "interval",
                    dose_class: "zone2",
                    duration_seconds: "1800",
                    completed: "1"
                  }
                }
              }
            }
          }
        }
      }
    end

    def persisted_draft_params(session)
      block = session.training_session_blocks.first
      exercise = block.training_session_exercises.first
      set = exercise.training_sets.first
      {
        snapshot_title: session.snapshot_title,
        performed_on: session.performed_on,
        training_session_blocks_attributes: {
          "0" => {
            id: block.id,
            snapshot_title: block.snapshot_title,
            snapshot_block_kind: block.snapshot_block_kind,
            snapshot_dose_class: block.snapshot_dose_class,
            actual_duration_seconds: block.actual_duration_seconds,
            training_session_exercises_attributes: {
              "0" => {
                id: exercise.id,
                exercise_id: exercise.exercise_id,
                snapshot_name: exercise.snapshot_name,
                snapshot_modality: exercise.snapshot_modality,
                snapshot_movement_pattern: exercise.snapshot_movement_pattern,
                snapshot_entry_kind: exercise.snapshot_entry_kind,
                snapshot_dose_class: exercise.snapshot_dose_class,
                training_sets_attributes: {
                  "0" => {
                    id: set.id,
                    entry_kind: set.entry_kind,
                    dose_class: set.dose_class,
                    reps: "8",
                    load_amount: "35",
                    load_unit: "lb",
                    completed: "1"
                  }
                }
              }
            }
          }
        }
      }
    end

    def turbo_stream_headers
      { "Accept" => Mime[:turbo_stream].to_s }
    end

    def persisted_session_params(session)
      {
        snapshot_title: session.snapshot_title,
        performed_on: session.performed_on,
        training_session_blocks_attributes: session.training_session_blocks.each_with_index.to_h do |block, block_index|
          [
            block_index.to_s,
            {
              id: block.id,
              snapshot_title: block.snapshot_title,
              snapshot_block_kind: block.snapshot_block_kind,
              snapshot_dose_class: block.snapshot_dose_class,
              actual_duration_seconds: block.actual_duration_seconds,
              training_session_exercises_attributes: block.training_session_exercises.each_with_index.to_h do |exercise, exercise_index|
                [
                  exercise_index.to_s,
                  {
                    id: exercise.id,
                    exercise_id: exercise.exercise_id,
                    snapshot_name: exercise.snapshot_name,
                    snapshot_modality: exercise.snapshot_modality,
                    snapshot_movement_pattern: exercise.snapshot_movement_pattern,
                    snapshot_entry_kind: exercise.snapshot_entry_kind,
                    snapshot_dose_class: exercise.snapshot_dose_class,
                    training_sets_attributes: exercise.training_sets.each_with_index.to_h do |set, set_index|
                      [
                        set_index.to_s,
                        {
                          id: set.id,
                          entry_kind: set.entry_kind,
                          dose_class: set.dose_class,
                          reps: set.reps,
                          duration_seconds: set.duration_seconds,
                          completed: set.completed
                        }
                      ]
                    end
                  }
                ]
              end
            }
          ]
        end
      }
    end
end
