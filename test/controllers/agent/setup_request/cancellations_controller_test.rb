require "test_helper"

class Agent::SetupRequest::CancellationsControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:two) }

  test "cancels a household request and returns to its provider" do
    request = setup_request(household: households(:home), requested_by: users(:two), key: "cancel-controller")

    post agent_setup_request_cancellation_path(request)

    assert_equal "cancelled", request.reload.status
    assert_redirected_to agent_profiles_path(anchor: "agent_provider_grok")
  end

  test "requires authentication and leaves the request pending" do
    request = setup_request(household: households(:home), requested_by: users(:two), key: "cancel-logged-out")
    sign_out

    post agent_setup_request_cancellation_path(request)

    assert_equal "pending", request.reload.status
    assert_redirected_to new_session_path
  end

  test "foreign household request id is not found and remains unchanged" do
    foreign_household = insert_foreign_household
    request = setup_request(household: foreign_household, requested_by: nil, key: "cancel-foreign", origin: "cli")

    post agent_setup_request_cancellation_path(request)

    assert_response :not_found
    assert_equal "pending", request.reload.status
  end

  private
    def setup_request(household:, requested_by:, key:, origin: "web")
      Agent::SetupRequest.create!(household: household, requested_by: requested_by,
        certified_key: "grok", action: "detect", idempotency_key: key, origin: origin)
    end

    def insert_foreign_household
      connection = ActiveRecord::Base.connection
      connection.execute("PRAGMA ignore_check_constraints = ON")
      Household.insert!({ name: "Foreign household", installation_key: 2,
        created_at: Time.current, updated_at: Time.current })
      Household.find_by!(installation_key: 2)
    ensure
      connection&.execute("PRAGMA ignore_check_constraints = OFF")
    end
end
