require "socket"
require "net/http"
require "test_helper"
require_relative "../test_helpers/exercise_visual_test_helper"
require_relative "../test_helpers/workout_guide_import_test_helper"

module OfflineCatalogNetworkGuard
  module TCPSocketOpen
    def open(...)
      if Thread.current[:forbid_outbound_network]
        raise "outbound TCPSocket.open must not be called"
      end

      super
    end
  end

  module NetHTTPRequest
    def request(...)
      if Thread.current[:forbid_outbound_network]
        raise "outbound Net::HTTP#request must not be called"
      end

      super
    end
  end
end

TCPSocket.singleton_class.prepend(OfflineCatalogNetworkGuard::TCPSocketOpen)
Net::HTTP.prepend(OfflineCatalogNetworkGuard::NetHTTPRequest)

class OfflineCatalogToWorkoutTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  include ExerciseVisualTestHelper
  include WorkoutGuideImportTestHelper

  test "imports the fixture catalog offline and renders a workout thumbnail" do
    assert_match(/sqlite/i, ActiveRecord::Base.connection.adapter_name)
    assert_kind_of ActiveStorage::Service::DiskService, ActiveStorage::Blob.service

    sign_in_as users(:one)
    Thread.current[:forbid_outbound_network] = true
    with_fixture_workout_guide_import do
      get exercises_path
      assert_response :success
      assert_select "form[action='#{workout_guide_import_path}']"

      assert_enqueued_with(job: WorkoutGuide::ImportJob) do
        post workout_guide_import_path
      end
      assert_redirected_to exercises_path
      perform_enqueued_jobs
    end

    exercise = households(:home).exercises.find_by!(source_key: "workout_guide:bench-press")
    get exercises_path
    assert_response :success
    assert_select "h2", text: exercise.name
    assert_select "[data-catalog-credit]"

    post workout_templates_path, params: {
      workout_template: {
        title: "Offline bench",
        provenance_status: "personal",
        workout_blocks_attributes: {
          "0" => {
            title: "Press",
            block_kind: "strength",
            dose_class: "strength",
            exercise_prescriptions_attributes: {
              "0" => {
                exercise_id: exercise.id,
                performance_kind: "reps",
                sets_count: "3",
                rep_min: "5",
                rep_max: "5",
                dose_class: "strength"
              }
            }
          }
        }
      }
    }

    template = households(:home).workout_templates.find_by!(title: "Offline bench")
    assert_redirected_to workout_template_path(template)
    get workout_template_path(template)
    assert_response :success
    assert_select "[data-exercise-thumbnail] img"

    post training_sessions_path, params: { template_id: template.id }
    session = people(:one).training_sessions.order(:created_at).last
    assert_redirected_to edit_training_session_path(session)
    get edit_training_session_path(session)
    assert_response :success
    assert_select "[data-exercise-thumbnail] img"
    get training_session_path(session)
    assert_response :success
    assert_select "[data-exercise-thumbnail] img"
  ensure
    Thread.current[:forbid_outbound_network] = false
  end
end
