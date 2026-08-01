require "test_helper"

class Agent::OperationalAuthorizationTest < ActiveSupport::TestCase
  setup do
    Current.session = sessions(:browser)
    Current.household = households(:home)
    Current.person = people(:two)
  end

  teardown { Current.reset }

  test "exact-context consent rotates a read grant and recovery issues digest-only read-write access" do
    agent_session = agent_sessions(:connected)
    old_grant = agent_grants(:active)

    authorization = Agent::OperationalAuthorization.authorize!(
      agent_session: agent_session,
      reason: "Daily operations"
    )

    assert_predicate authorization, :active?
    assert_equal users(:two), authorization.authorized_by
    assert_not_nil old_grant.reload.revoked_at
    assert_equal "reauthorization_required", agent_session.reload.mcp_authorization_status

    agent_session.update!(status: "starting")
    credential = agent_session.issue_runtime_grant!
    assert_equal %w[health_read health_write], credential.grant.capability_groups
    assert_nil credential.grant.issued_by
    assert_equal 64, credential.grant.token_digest.length
    refute_equal credential.bearer, credential.grant.token_digest
  end

  test "wrong person context cannot authorize a session" do
    Current.person = people(:one)

    assert_raises ActiveRecord::RecordInvalid do
      Agent::OperationalAuthorization.authorize!(
        agent_session: agent_sessions(:connected),
        reason: "Wrong context"
      )
    end
  end

  test "revocation terminalizes pending proposals and restores read-only recovery" do
    agent_session = agent_sessions(:connected)
    authorization = Agent::OperationalAuthorization.authorize!(agent_session: agent_session, reason: "Daily operations")
    agent_session.update!(status: "starting")
    grant = agent_session.issue_runtime_grant!.grant
    proposal, = Agent::MutationProposal.propose!(
      grant: grant,
      operation: "delete_meal",
      arguments: { id: meals(:sam_recipe_target_week).id },
      preview: {},
      expected_state: Agent::Mutation::Operations.expected_state(
        operation: "delete_meal",
        arguments: { id: meals(:sam_recipe_target_week).id },
        proposal: grant
      ),
      idempotency_key: "delete-meal-revoke",
      deadline_at: 1.minute.from_now
    )

    authorization.revoke!(reason: "user disabled", by: users(:two))

    assert_equal "cancelled", proposal.reload.status
    agent_session.update!(status: "starting")
    assert_equal [ "health_read" ], agent_session.issue_runtime_grant!.grant.capability_groups
  end
end
