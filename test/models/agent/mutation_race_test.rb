require "test_helper"

class Agent::MutationRaceTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  setup do
    @browser_session = users(:two).sessions.create!
    @conversation = Agent::Conversation.create!(
      household: households(:home), person: people(:two), profile: agent_profiles(:hearth), title: "Mutation race"
    )
    @agent_session = Agent::Session.create!(
      household: households(:home), person: people(:two), conversation: @conversation,
      installation: agent_installations(:local), browser_session: @browser_session,
      external_session_id: "mutation-race-#{SecureRandom.hex(4)}", status: "connected",
      authentication_status: "authenticated", mcp_authorization_status: "authorized"
    )
    Current.session = @browser_session
    Current.household = households(:home)
    Current.person = people(:two)
    Agent::OperationalAuthorization.authorize!(agent_session: @agent_session, reason: "Race proof")
    @agent_session.update!(status: "starting")
    @grant = @agent_session.issue_runtime_grant!.grant
  end

  teardown do
    Current.reset
    Agent::AuditEvent.where(conversation: @conversation).delete_all
    Agent::MutationExecution.where(mutation_proposal: @agent_session.mutation_proposals).delete_all
    Agent::PermissionDecision.where(permission_request: @agent_session.permission_requests).delete_all
    Agent::PermissionRequest.where(agent_session: @agent_session).update_all(mutation_proposal_id: nil)
    Agent::MutationProposal.where(agent_session: @agent_session).delete_all
    Agent::PermissionRequest.where(agent_session: @agent_session).delete_all
    Agent::OperationalAuthorization.where(agent_session: @agent_session).delete_all
    Agent::Grant.where(agent_session: @agent_session).delete_all
    Agent::Session.where(id: @agent_session.id).delete_all
    Agent::Conversation.where(id: @conversation.id).delete_all
    @browser_session.destroy!
  end

  test "approval racing timeout has exactly one stable terminal outcome" do
    3.times do |iteration|
      meal = Meal.create!(
        household: households(:home), person: people(:two), eaten_on: Date.current,
        meal_items_attributes: [ { source_kind: "free_text", snapshot_label: "Race meal #{iteration}" } ]
      )
      expected = Agent::Mutation::Operations.expected_state(
        operation: "delete_meal", arguments: { id: meal.id }, proposal: @grant
      )
      proposal, token = Agent::MutationProposal.propose!(
        grant: @grant, capability: "health.write", operation: "delete_meal", arguments: { id: meal.id }, preview: {}, expected_state: expected,
        idempotency_key: "race-delete-#{iteration}", deadline_at: 1.minute.from_now
      )
      ready = Queue.new
      start = Queue.new
      errors = Queue.new
      threads = [
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            ready << true
            start.pop
            Agent::MutationProposal.find(proposal.id).decide!(outcome: "approved", by: users(:two), token: token)
          rescue ActiveRecord::ActiveRecordError => error
            errors << error
          end
        end,
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            ready << true
            start.pop
            Agent::MutationProposal.find(proposal.id).cancel!(reason: "permission timeout", status: "expired")
          rescue ActiveRecord::ActiveRecordError => error
            errors << error
          end
        end
      ]
      2.times { ready.pop }
      2.times { start << true }
      threads.each(&:join)

      proposal.reload
      assert_includes %w[executed expired], proposal.status
      assert_equal(proposal.status == "executed", proposal.execution.present?)
      assert_equal(proposal.status == "executed", !Meal.exists?(meal.id))
      assert_operator errors.size, :<=, 1
      meal.destroy! if Meal.exists?(meal.id)
    end
  end
end
