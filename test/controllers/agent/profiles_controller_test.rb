require "test_helper"

class Agent::ProfilesControllerTest < ActionDispatch::IntegrationTest
  test "requires authentication" do
    get agent_profiles_path
    assert_redirected_to new_session_path
  end

  test "renders certified providers as persistent connections" do
    sign_in_as users(:two)
    get agent_profiles_path

    assert_response :success
    assert_select "h1", "Agents"
    assert_select "article", count: Agent::Profile::Certified.keys.size
    assert_select "#agent_provider_grok", text: /Connected/
    assert_select "#agent_provider_grok", text: /starts this agent when a conversation needs it/
    assert_select "#agent_provider_grok form", text: /Re-authenticate/, count: 0
    assert_select "#agent_provider_grok input[name='setup_request[authentication_method_id]']", count: 0
    assert_select "p", text: /separate approval/
    assert_no_match(/usr\/local\/bin|TEST_AGENT_HOME|one@example.com/, response.body)
  end
end
