require "test_helper"

class Agent::MutationDecisionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:two)
    Current.household = households(:home)
    Current.person = people(:two)
    @agent_session = Agent::Session.create!(
      household: Current.household,
      person: Current.person,
      conversation: agent_conversations(:active),
      installation: agent_installations(:local),
      browser_session: Current.session,
      external_session_id: "decision-controller-session",
      status: "connected",
      authentication_status: "authenticated",
      mcp_authorization_status: "authorized"
    )
    Agent::OperationalAuthorization.authorize!(agent_session: @agent_session, reason: "Daily operations")
    @agent_session.update!(status: "starting")
    @grant = @agent_session.issue_runtime_grant!.grant
  end

  test "trusted browser approval executes once and returns a full Turbo replacement" do
    meal = meals(:sam_recipe_target_week)
    expected = Agent::Mutation::Operations.expected_state(operation: "delete_meal", arguments: { id: meal.id }, proposal: @grant)
    proposal, token = Agent::MutationProposal.propose!(
      grant: @grant, capability: "health.write", operation: "delete_meal", arguments: { id: meal.id },
      preview: Agent::Mutation::Operations.preview(operation: "delete_meal", arguments: { id: meal.id }, context: @grant),
      expected_state: expected, idempotency_key: "controller-delete-meal", deadline_at: 1.minute.from_now
    )

    post agent_mutation_proposal_decision_path(proposal), params: {
      outcome: "approved", confirmation_token: token
    }, as: :turbo_stream

    assert_response :success
    assert_includes response.body, 'action="replace"'
    assert_equal "executed", proposal.reload.status
    assert_not Meal.exists?(meal.id)
  end

  test "cancel leaves the domain unchanged" do
    meal = meals(:sam_recipe_target_week)
    expected = Agent::Mutation::Operations.expected_state(operation: "delete_meal", arguments: { id: meal.id }, proposal: @grant)
    proposal, = Agent::MutationProposal.propose!(
      grant: @grant, capability: "health.write", operation: "delete_meal", arguments: { id: meal.id }, preview: {},
      expected_state: expected, idempotency_key: "controller-cancel-meal", deadline_at: 1.minute.from_now
    )

    delete agent_mutation_proposal_decision_path(proposal), as: :turbo_stream

    assert_response :success
    assert_includes response.body, 'action="replace"'
    assert_equal "cancelled", proposal.reload.status
    assert Meal.exists?(meal.id)
  end

  test "authenticated GET renders an overdue proposal as inert without reconciling rows" do
    meal = meals(:sam_recipe_target_week)
    arguments = { id: meal.id }
    proposal, = Agent::MutationProposal.propose!(
      grant: @grant, capability: "health.write", operation: "delete_meal", arguments: arguments, preview: {},
      expected_state: Agent::Mutation::Operations.expected_state(operation: "delete_meal", arguments: arguments, proposal: @grant),
      idempotency_key: "controller-overdue-read", deadline_at: 1.minute.from_now
    )
    proposal.update_column(:deadline_at, 1.second.ago)
    audit_count = Agent::AuditEvent.count

    get root_path

    assert_response :success
    assert_equal "pending", proposal.reload.status
    assert_equal "pending", proposal.permission_request.reload.status
    assert_equal audit_count, Agent::AuditEvent.count
    assert_not_includes response.body, "Confirm agent operation"
  end
end
