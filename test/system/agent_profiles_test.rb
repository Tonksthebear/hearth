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

  test "authenticated provider allows proactive explicit reauthentication" do
    Agent::SetupRequest.create!(household: households(:home), requested_by: users(:two), certified_key: "grok",
      action: "detect", idempotency_key: "reauth-detection", origin: "web", status: "succeeded",
      cli_available: true, adapter_available: true, adapter_version: "1.0")
    sign_in_via_browser users(:two)
    visit_and_wait_for_path agent_profiles_path

    within "#agent_provider_grok" do
      choose "Cached login"
      click_button "Re-authenticate"
    end

    assert_text "Agent setup request queued.", wait: 5
    request = Agent::SetupRequest.uncached { Agent::SetupRequest.order(:id).last }
    assert_equal "reauthenticate", request.action
    assert_equal "cached_token", request.authentication_method_id
    assert_equal "pending", request.status
  end

  test "runtime footer preserves its structure across supervised lifecycle states" do
    sign_in_via_browser users(:two)
    household = households(:home)
    footer = "#agent_provider_grok > div.border-t.border-gray-100.bg-gray-50"
    offline_states = {
      "never_started" => "Hearth supervisor has not started ACP yet",
      "starting" => "Hearth supervisor is starting ACP",
      "recovering" => "Hearth supervisor is recovering ACP",
      "stopped" => "Hearth ACP runtime stopped",
      "failed" => "Hearth ACP runtime failed"
    }

    offline_states.each do |state, heading|
      Agent::RuntimeStatus.where(household: household).delete_all
      unless state == "never_started"
        persisted = state == "recovering" ? "online" : state
        heartbeat = state == "recovering" ? 1.minute.ago : Time.current
        Agent::RuntimeStatus.create!(household: household, owner: "runtime", status: persisted,
          started_at: 1.minute.ago, heartbeat_at: heartbeat,
          stopped_at: persisted.in?(%w[ stopped failed ]) ? Time.current : nil,
          failure_category: persisted == "failed" ? "runtime_error" : nil)
      end

      visit_and_wait_for_path agent_profiles_path
      within footer do
        assert_selector "div[role='status'] > div.shrink-0"
        assert_selector "div[role='status'] h3", text: heading
        assert_selector "div[role='status'] p", count: 1
        assert_button "Queue availability check"
      end
    end

    Agent::RuntimeStatus.where(household: household).delete_all
    Agent::RuntimeStatus.create!(household: household, owner: "runtime", status: "online",
      started_at: Time.current, heartbeat_at: Time.current)
    visit_and_wait_for_path agent_profiles_path
    within footer do
      assert_selector "p", text: "Sibling ACP runtime online"
      assert_no_selector "div[role='status']"
    end
  end

  test "runtime status transitions update an open Agent Settings page" do
    household = households(:home)
    Agent::RuntimeStatus.where(household: household).delete_all
    Agent::RuntimeStatus.start_all!(owner: "runtime")
    sign_in_via_browser users(:two)
    visit_and_wait_for_path agent_profiles_path

    within "#agent_provider_grok" do
      assert_text "Hearth supervisor is starting ACP"
    end

    Agent::RuntimeStatus.heartbeat_all!(owner: "runtime")

    within "#agent_provider_grok" do
      assert_text "Sibling ACP runtime online", wait: 5
      assert_no_text "Hearth supervisor is starting ACP"
    end
  end
end
