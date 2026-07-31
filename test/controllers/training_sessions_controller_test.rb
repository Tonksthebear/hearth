require "test_helper"

class TrainingSessionsControllerTest < ActionDispatch::IntegrationTest
  test "new uses the selected logging date" do
    sign_in_as users(:one)

    get new_training_session_path(date: "2026-08-03")

    assert_response :success
    assert_select "input[name='training_session[performed_on]'][value='2026-08-03']"
  end

  test "new falls back to the current date when the selected date is malformed" do
    travel_to Time.zone.local(2026, 7, 27, 12) do
      sign_in_as users(:one)

      get new_training_session_path(date: "not-a-date")

      assert_response :success
      assert_select "input[name='training_session[performed_on]'][value='2026-07-27']"
    end
  end

  test "starts a template snapshot for Current person" do
    sign_in_as users(:one)

    assert_difference "TrainingSession.count", 1 do
      post training_sessions_path, params: { template_id: workout_templates(:balanced).id }
    end

    session = people(:one).training_sessions.order(:created_at).last
    assert_redirected_to edit_training_session_path(session)
    assert_equal "Balanced training day", session.snapshot_title
    assert_equal 2, session.training_session_blocks.size
  end

  test "starts and links a planned workout for Current person" do
    travel_to Time.zone.local(2026, 7, 30, 12) do
      sign_in_as users(:one)
      plan = planned_workouts(:planned_balanced)

      assert_difference "TrainingSession.count", 1 do
        post training_sessions_path, params: { planned_workout_id: plan.id }
      end

      assert_redirected_to edit_training_session_path(plan.reload.training_session)
      assert_equal :in_progress, plan.status
    end
  end

  test "refuses future already-started and skipped plans with an in-app redirect" do
    travel_to Time.zone.local(2026, 7, 30, 12) do
      sign_in_as users(:one)

      [
        planned_workouts(:future_balanced),
        planned_workouts(:linked_in_progress),
        planned_workouts(:skipped_balanced)
      ].each do |plan|
        assert_no_difference "TrainingSession.count" do
          post training_sessions_path,
            params: { planned_workout_id: plan.id, return_to: "activity_week", date: plan.scheduled_on }
        end

        assert_redirected_to activity_week_path(date: plan.scheduled_on)
        assert_match(/Only a due, planned workout can be started/, flash[:alert])
      end
    end
  end

  test "does not start another person's planned workout" do
    sign_in_as users(:one)

    assert_no_difference "TrainingSession.count" do
      post training_sessions_path, params: { planned_workout_id: planned_workouts(:sam_balanced).id }
    end

    assert_response :not_found
  end

  test "creates a structured inline ad hoc workout without changing the catalog" do
    sign_in_as users(:one)

    assert_difference "TrainingSession.count", 1 do
      assert_no_difference "Exercise.count" do
        post training_sessions_path, params: { training_session: ad_hoc_params }
      end
    end

    session = people(:one).training_sessions.order(:created_at).last
    assert_redirected_to edit_training_session_path(session)
    exercise = session.training_session_blocks.first.training_session_exercises.first
    assert_nil exercise.exercise_id
    assert_equal "about_right", exercise.difficulty
    assert_equal "Keep the pace", exercise.next_time_adjustment
  end

  test "new renders live performance controls and native actual templates" do
    sign_in_as users(:one)

    get new_training_session_path

    assert_response :success
    assert_select "el-select[name$='[snapshot_performance_kind]'][value='reps']", count: 1
    assert_select "template[data-kind]", minimum: 10
    assert_select "el-select[name$='[load_unit]']"
    assert_select "el-select[name$='[distance_unit]']"
    assert_select "el-select[name$='[count_unit]']"
    assert_select "[data-kinds='duration distance count interval'][data-hidden] input[name$='[snapshot_work_seconds]'][disabled]", count: 1
    assert_select "[data-kinds='duration distance count interval'][data-hidden] input[name$='[duration_seconds]'][disabled]", count: 1

    ids = css_select("[id]").map { |node| node["id"] }
    assert_empty ids.tally.select { |_id, count| count > 1 }
  end

  test "Turbo structural actions replace the complete in-progress form without persisting" do
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

  test "edit renders unique ids across live controls and inert templates" do
    sign_in_as users(:one)

    get edit_training_session_path(training_sessions(:in_progress))

    assert_response :success
    ids = css_select("[id]").map { |node| node["id"] }
    assert_empty ids.tally.select { |_id, count| count > 1 }
  end

  test "completes a saved in-progress workout and then makes it read only" do
    sign_in_as users(:one)
    session = training_sessions(:in_progress)

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
    session = training_sessions(:in_progress)
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
    session = training_sessions(:in_progress)
    second_block = session.training_session_blocks.create!(
      position: 2,
      snapshot_title: "Second block",
      snapshot_block_kind: :other,
      snapshot_dose_class: :none,
    )
    second_exercise = second_block.training_session_exercises.create!(
      position: 1,
      snapshot_name: "Walk",
      snapshot_modality: :cardio,
      snapshot_movement_pattern: :locomotion_cardio,
      snapshot_performance_kind: :interval,
      snapshot_dose_class: :none,
      snapshot_work_seconds: 600,
      snapshot_rest_seconds: 0
    )
    second_exercise.training_sets.create!(position: 1, dose_class: :none)
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

  test "deletes an in-progress workout and redirects to its training week" do
    sign_in_as users(:one)
    session = training_sessions(:in_progress)

    assert_difference "TrainingSession.count", -1 do
      delete training_session_path(session)
    end

    assert_redirected_to training_week_path(date: session.performed_on)
  end

  test "refuses to delete a completed session" do
    sign_in_as users(:one)
    session = training_sessions(:completed_sunday)

    assert_no_difference "TrainingSession.count" do
      delete training_session_path(session)
    end

    assert_redirected_to training_session_path(session)
    assert TrainingSession.exists?(session.id)
  end

  test "does not expose another person's session to deletion" do
    sign_in_as users(:one)
    session = training_sessions(:other_person)

    assert_no_difference "TrainingSession.count" do
      delete training_session_path(session)
    end

    assert_response :not_found
    assert TrainingSession.exists?(session.id)
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
                snapshot_performance_kind: "interval",
                snapshot_work_seconds: "1800",
                snapshot_rest_seconds: "0",
                snapshot_dose_class: "zone2",
                difficulty: "about_right",
                next_time_adjustment: "Keep the pace",
                training_sets_attributes: {
                  "0" => {
                    dose_class: "zone2",
                    duration_seconds: "1800",
                    rest_seconds: "0",
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
                snapshot_performance_kind: exercise.snapshot_performance_kind,
                snapshot_dose_class: exercise.snapshot_dose_class,
                training_sets_attributes: {
                  "0" => {
                    id: set.id,
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
                    snapshot_performance_kind: exercise.snapshot_performance_kind,
                    snapshot_dose_class: exercise.snapshot_dose_class,
                    training_sets_attributes: exercise.training_sets.each_with_index.to_h do |set, set_index|
                      [
                        set_index.to_s,
                        {
                          id: set.id,
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
