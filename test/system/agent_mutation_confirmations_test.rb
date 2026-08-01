require "application_system_test_case"

class AgentMutationConfirmationsTest < ApplicationSystemTestCase
  test "trusted Hotwire approval arrives without reload and executes exactly once" do
    sign_in_via_browser users(:two)
    browser_session = users(:two).sessions.order(:created_at).last
    agent_session = Agent::Session.create!(
      household: households(:home),
      person: people(:two),
      conversation: agent_conversations(:active),
      installation: agent_installations(:local),
      browser_session: browser_session,
      external_session_id: "system-confirmation-session",
      status: "connected",
      authentication_status: "authenticated",
      mcp_authorization_status: "authorized"
    )
    visit_and_wait_for_path root_path
    click_button "Enable operations"
    assert_text "Agent operations enabled for #{people(:two).name}", wait: 5

    authorization = agent_session.operational_authorizations.active_at.sole
    agent_session.update!(status: "starting")
    grant = agent_session.issue_runtime_grant!.grant
    meal = meals(:sam_recipe_target_week)
    expected = Agent::Mutation::Operations.expected_state(
      operation: "delete_meal", arguments: { id: meal.id }, proposal: grant
    )
    proposal, token = Agent::MutationProposal.propose!(
      grant: grant, capability: "health.write",
      operation: "delete_meal",
      arguments: { id: meal.id },
      preview: Agent::Mutation::Operations.preview(operation: "delete_meal", arguments: { id: meal.id }, context: grant),
      expected_state: expected,
      idempotency_key: "system-delete-meal",
      deadline_at: [ authorization.expires_at, 1.minute.from_now ].min
    )

    time_origin = page.evaluate_script("performance.timeOrigin")
    connect_turbo_cable_stream_sources
    proposal.broadcast_confirmation(token)
    assert_text "Confirm agent operation for #{people(:two).name}", wait: 5
    assert_text proposal.preview.fetch("effect")
    assert_text "Decision due"

    click_button "Approve once"

    assert_no_text "Confirm agent operation", wait: 5
    assert_equal time_origin, page.evaluate_script("performance.timeOrigin")
    assert_equal "executed", proposal.reload.status
    assert_not Meal.exists?(meal.id)
    assert_equal 1, Agent::MutationExecution.where(mutation_proposal: proposal).count
  end

  test "cancellation is Turbo-visible and leaves the graph unchanged" do
    sign_in_via_browser users(:two)
    browser_session = users(:two).sessions.order(:created_at).last
    agent_session = Agent::Session.create!(
      household: households(:home), person: people(:two), conversation: agent_conversations(:active),
      installation: agent_installations(:local), browser_session: browser_session,
      external_session_id: "system-cancel-session", status: "starting",
      authentication_status: "authenticated", mcp_authorization_status: "authorized"
    )
    visit_and_wait_for_path root_path
    click_button "Enable operations"
    assert_text "Agent operations enabled", wait: 5
    grant = agent_session.issue_runtime_grant!.grant
    meal = meals(:sam_recipe_target_week)
    expected = Agent::Mutation::Operations.expected_state(operation: "delete_meal", arguments: { id: meal.id }, proposal: grant)
    proposal, token = Agent::MutationProposal.propose!(
      grant: grant, capability: "health.write", operation: "delete_meal", arguments: { id: meal.id }, preview: {}, expected_state: expected,
      idempotency_key: "system-cancel-meal", deadline_at: 1.minute.from_now
    )
    connect_turbo_cable_stream_sources
    proposal.broadcast_confirmation(token)
    assert_text "Confirm agent operation", wait: 5

    click_button "Cancel"

    assert_no_text "Confirm agent operation", wait: 5
    assert_equal "cancelled", proposal.reload.status
    assert Meal.exists?(meal.id)
  end
end
