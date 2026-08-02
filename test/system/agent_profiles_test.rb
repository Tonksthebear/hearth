require "application_system_test_case"

class AgentProfilesTest < ApplicationSystemTestCase
  self.use_transactional_tests = false

  test "signed in user explicitly approves authentication and can cancel queued work" do
    installation = agent_installations(:local)
    installation.update!(
      authentication_methods: [ { "id" => "fake-auth", "name" => "Fake authentication",
        "description" => "/private/credential-canary/token.json" } ].map { |method| method.slice("id", "name") },
      authentication_status: "required",
      authentication_method_id: nil,
      authentication_approved_at: nil,
      authentication_origin: nil
    )
    Agent::SetupRequest.create!(household: households(:home), requested_by: users(:two), certified_key: "grok",
      action: "detect", idempotency_key: "browser-detection", origin: "web", status: "succeeded",
      cli_available: true, cli_version: "grok 1.0", adapter_available: true, adapter_version: "1.0")
    sign_in_via_browser users(:two)

    visit_and_wait_for_path agent_profiles_path
    assert_selector "h1", text: "Agents"
    assert_selector "dt", text: /Provider CLI/i, count: 3
    assert_selector "dt", text: /ACP adapter/i, count: 3
    assert_text "Conversation permissions are separate"
    assert_no_text "credential-canary"
    within "#agent_provider_grok" do
      choose "Fake authentication"
      click_button "Approve authentication"
    end
    assert_current_path agent_profiles_path
    assert_text "Agent setup request queued.", wait: 5
    request = Agent::SetupRequest.uncached { Agent::SetupRequest.order(:id).last }
    assert_equal "authenticate", request.action
    assert_equal "fake-auth", request.authentication_method_id
    assert_equal "pending", request.status

    within "#agent_provider_grok" do
      click_button "Cancel request"
    end
    assert_text "Setup request cancelled.", wait: 5
    assert_equal "cancelled", request.reload.status
    assert_selector "#agent_provider_grok", text: "Cancelled"
  end

  test "disable is confirmed and narrow cards do not overflow" do
    Agent::SetupRequest.create!(household: households(:home), requested_by: users(:two), certified_key: "grok",
      action: "detect", idempotency_key: "mobile-detection", origin: "web", status: "succeeded",
      cli_available: true, adapter_available: true, adapter_version: "1.0")
    sign_in_via_browser users(:two)
    original_size = page.current_window.size
    page.current_window.resize_to(390, 844)
    visit_and_wait_for_path agent_profiles_path

    assert_not page.evaluate_script("document.documentElement.scrollWidth > document.documentElement.clientWidth")
    dismiss_confirm do
      within("#agent_provider_grok") { click_button "Disable and revoke" }
    end
    assert_nil Agent::SetupRequest.find_by(action: "disable")
    accept_confirm do
      within("#agent_provider_grok") { click_button "Disable and revoke" }
    end
    assert_text "Agent setup request queued.", wait: 5
    assert_equal "pending", Agent::SetupRequest.uncached { Agent::SetupRequest.find_by!(action: "disable") }.status
  ensure
    page.current_window.resize_to(original_size[0], original_size[1]) if original_size
  end
end
