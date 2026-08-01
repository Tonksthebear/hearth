class AddLoresterKnowledgeGateway < ActiveRecord::Migration[8.1]
  def up
    create_table :agent_knowledge_submissions do |t|
      t.references :household, null: false, foreign_key: true
      t.references :person, null: false, foreign_key: true
      t.references :conversation, null: false, foreign_key: { to_table: :agent_conversations }
      t.references :agent_session, null: false, foreign_key: { to_table: :agent_sessions }
      t.references :agent_grant, null: false, foreign_key: { to_table: :agent_grants }
      t.references :message, null: false, foreign_key: { to_table: :agent_messages }
      t.string :request_id, null: false
      t.string :origin, null: false
      t.string :requested_intent, null: false
      t.text :content, null: false
      t.string :content_digest, null: false
      t.text :content_preview, null: false
      t.string :status, null: false, default: "pending"
      t.string :lorester_submission_id
      t.string :diagnostic
      t.json :provenance, null: false, default: {}
      t.datetime :dispatched_at
      t.datetime :last_polled_at
      t.datetime :terminal_at
      t.timestamps
    end
    add_index :agent_knowledge_submissions, [ :agent_session_id, :request_id ], unique: true,
      name: "index_agent_knowledge_submissions_on_session_and_request"
    add_index :agent_knowledge_submissions, :lorester_submission_id, unique: true,
      where: "lorester_submission_id IS NOT NULL"
    add_check_constraint :agent_knowledge_submissions,
      "status IN ('pending', 'accepted', 'materialized', 'admitted', 'processing', 'complete', 'failed', 'unavailable')",
      name: "agent_knowledge_submissions_status"

    add_reference :agent_permission_requests, :permission_subject, polymorphic: true, index: false
    execute <<~SQL.squish
      UPDATE agent_permission_requests
      SET permission_subject_type = 'Agent::MutationProposal',
          permission_subject_id = mutation_proposal_id
      WHERE mutation_proposal_id IS NOT NULL
    SQL
    add_index :agent_permission_requests,
      [ :permission_subject_type, :permission_subject_id ],
      unique: true,
      name: "index_agent_permission_requests_on_permission_subject"
    add_check_constraint :agent_permission_requests,
      "(permission_subject_type IS NULL AND permission_subject_id IS NULL) OR " \
        "(permission_subject_type IN ('Agent::MutationProposal', 'Agent::KnowledgeSubmission') AND permission_subject_id IS NOT NULL)",
      name: "agent_permission_requests_known_subject"
    remove_reference :agent_permission_requests, :mutation_proposal, foreign_key: { to_table: :agent_mutation_proposals }

    add_column :agent_tool_activities, :provenance, :json, null: false, default: {}
  end

  def down
    remove_column :agent_tool_activities, :provenance

    add_reference :agent_permission_requests, :mutation_proposal,
      foreign_key: { to_table: :agent_mutation_proposals }, index: { unique: true }
    execute <<~SQL.squish
      UPDATE agent_permission_requests
      SET mutation_proposal_id = permission_subject_id
      WHERE permission_subject_type = 'Agent::MutationProposal'
    SQL
    remove_check_constraint :agent_permission_requests, name: "agent_permission_requests_known_subject"
    remove_index :agent_permission_requests, name: "index_agent_permission_requests_on_permission_subject"
    remove_reference :agent_permission_requests, :permission_subject, polymorphic: true

    drop_table :agent_knowledge_submissions
  end
end
