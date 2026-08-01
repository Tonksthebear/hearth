require "test_helper"
require Rails.root.join("db/migrate/20260731220000_add_lorester_knowledge_gateway")

class AddLoresterKnowledgeGatewayTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  test "cold migration round trip preserves every mutation permission link and subjectless rows" do
    grant = agent_grants(:active)
    proposal, = Agent::MutationProposal.propose!(
      grant: grant,
      capability: "health.write",
      operation: "delete_meal",
      arguments: { id: meals(:sam_recipe_target_week).id },
      preview: {},
      expected_state: Agent::Mutation::Operations.expected_state(
        operation: "delete_meal", arguments: { id: meals(:sam_recipe_target_week).id }, proposal: grant
      ),
      idempotency_key: "migration-knowledge-gateway",
      deadline_at: 1.minute.from_now
    )
    request_id = proposal.permission_request.id
    subjectless_id = agent_permission_requests(:pending).id
    migration = AddLoresterKnowledgeGateway.new

    migration.migrate(:down)
    assert_equal proposal.id, connection.select_value(
      "SELECT mutation_proposal_id FROM agent_permission_requests WHERE id = #{request_id}"
    ).to_i
    assert_nil connection.select_value(
      "SELECT mutation_proposal_id FROM agent_permission_requests WHERE id = #{subjectless_id}"
    )

    migration.migrate(:up)
    row = connection.select_one(
      "SELECT permission_subject_type, permission_subject_id FROM agent_permission_requests WHERE id = #{request_id}"
    )
    assert_equal "Agent::MutationProposal", row.fetch("permission_subject_type")
    assert_equal proposal.id, row.fetch("permission_subject_id").to_i
    assert_equal({ "permission_subject_type" => nil, "permission_subject_id" => nil }, connection.select_one(
      "SELECT permission_subject_type, permission_subject_id FROM agent_permission_requests WHERE id = #{subjectless_id}"
    ))
    refute connection.column_exists?(:agent_permission_requests, :mutation_proposal_id)
  ensure
    migration&.migrate(:up) if connection.column_exists?(:agent_permission_requests, :mutation_proposal_id)
    reset_agent_column_information
    if request_id
      connection.execute("DELETE FROM agent_audit_events WHERE subject_type = 'Agent::PermissionRequest' AND subject_id = #{request_id}")
      connection.execute("DELETE FROM agent_permission_requests WHERE id = #{request_id}")
    end
    if proposal
      connection.execute("DELETE FROM agent_audit_events WHERE subject_type = 'Agent::MutationProposal' AND subject_id = #{proposal.id}")
      connection.execute("DELETE FROM agent_mutation_proposals WHERE id = #{proposal.id}")
    end
  end

  test "database admits only paired known permission subjects" do
    request = agent_permission_requests(:pending)

    assert_raises(ActiveRecord::StatementInvalid) do
      connection.execute <<~SQL
        UPDATE agent_permission_requests
        SET permission_subject_type = 'Household', permission_subject_id = #{households(:home).id}
        WHERE id = #{request.id}
      SQL
    end
    assert_raises(ActiveRecord::StatementInvalid) do
      connection.execute <<~SQL
        UPDATE agent_permission_requests
        SET permission_subject_type = 'Agent::KnowledgeSubmission', permission_subject_id = NULL
        WHERE id = #{request.id}
      SQL
    end
  end

  private
    def connection = ActiveRecord::Base.connection

    def reset_agent_column_information
      connection.schema_cache.clear!
      [ Agent::PermissionRequest, Agent::KnowledgeSubmission, Agent::ToolActivity ].each(&:reset_column_information)
    end
end
