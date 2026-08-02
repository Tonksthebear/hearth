require "test_helper"

class Agent::SetupRequestsControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:two) }

  test "queues only a certified household command" do
    assert_difference("Agent::SetupRequest.count", 1) do
      post agent_setup_requests_path, params: { setup_request: {
        certified_key: "grok", action: "detect", idempotency_key: "web-detect"
      } }
    end

    request = Agent::SetupRequest.order(:id).last
    assert_equal households(:home), request.household
    assert_equal users(:two), request.requested_by
    assert_equal "web", request.origin
    assert_redirected_to agent_profiles_path(anchor: "agent_provider_grok")
  end

  test "duplicate idempotency key returns the original request" do
    2.times do
      post agent_setup_requests_path, params: { setup_request: {
        certified_key: "grok", action: "detect", idempotency_key: "duplicate"
      } }
    end

    assert_equal 1, Agent::SetupRequest.where(idempotency_key: "duplicate").count
  end

  test "hostile runtime and provider parameters cannot change profile configuration" do
    profile = agent_profiles(:hearth)
    before = profile.attributes.slice("executable_path", "arguments", "environment_keys", "working_directory", "enabled")

    post agent_setup_requests_path, params: { setup_request: {
      certified_key: "grok", action: "detect", idempotency_key: "hostile",
      executable_path: "/tmp/evil", arguments: [ "--shell" ], environment_keys: [ "SECRET=value" ],
      working_directory: "/tmp", enabled: false, provider: { token: "secret" }
    } }

    assert_equal before, profile.reload.attributes.slice(*before.keys)
    request = Agent::SetupRequest.find_by!(idempotency_key: "hostile")
    assert_nil request.authentication_method_id
    assert_no_match(/evil|SECRET|secret/, request.attributes.to_json)
  end

  test "does not invoke process or supervisor APIs in the controller" do
    singleton = Acp::Supervisor.singleton_class
    singleton.alias_method :__original_new, :new
    singleton.define_method(:new) { |*| raise "Puma constructed a supervisor" }

    assert_nothing_raised do
      post agent_setup_requests_path, params: { setup_request: {
        certified_key: "grok", action: "detect", idempotency_key: "boundary"
      } }
    end
  ensure
    singleton.alias_method :new, :__original_new if singleton&.method_defined?(:__original_new)
    singleton.remove_method :__original_new if singleton&.method_defined?(:__original_new)
  end

  test "requires authentication" do
    sign_out
    post agent_setup_requests_path, params: { setup_request: {
      certified_key: "grok", action: "detect", idempotency_key: "logged-out"
    } }

    assert_redirected_to new_session_path
    assert_nil Agent::SetupRequest.find_by(idempotency_key: "logged-out")
  end
end
