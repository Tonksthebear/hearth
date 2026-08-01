class AddGuardedAgentMutations < ActiveRecord::Migration[8.1]
  def change
    create_table :agent_operational_authorizations do |t|
      t.references :household, null: false, foreign_key: true
      t.references :person, null: false, foreign_key: true
      t.references :conversation, null: false, foreign_key: { to_table: :agent_conversations }
      t.references :agent_session, null: false, foreign_key: true
      t.references :browser_session, foreign_key: { to_table: :sessions, on_delete: :nullify }
      t.references :authorized_by, null: false, foreign_key: { to_table: :users }
      t.json :capability_groups, null: false, default: [ "health_write" ]
      t.text :reason, null: false
      t.datetime :authorized_at, null: false
      t.datetime :expires_at, null: false
      t.datetime :revoked_at
      t.text :revocation_reason
      t.integer :revision, null: false, default: 1
      t.timestamps

      t.index %i[agent_session_id revoked_at], name: "index_agent_operational_authorizations_on_session_and_active"
      t.index %i[browser_session_id revoked_at], name: "index_agent_operational_authorizations_on_browser_and_active"
      t.check_constraint "revision > 0", name: "agent_operational_authorizations_positive_revision"
    end

    create_table :agent_mutation_proposals do |t|
      t.references :household, null: false, foreign_key: true
      t.references :person, null: false, foreign_key: true
      t.references :conversation, null: false, foreign_key: { to_table: :agent_conversations }
      t.references :agent_session, null: false, foreign_key: true
      t.references :agent_grant, null: false, foreign_key: true
      t.references :requested_by, foreign_key: { to_table: :users }
      t.references :approved_by, foreign_key: { to_table: :users }
      t.references :executed_by, foreign_key: { to_table: :users }
      t.string :operation, null: false
      t.string :status, null: false, default: "pending"
      t.text :input_body, null: false
      t.string :input_digest, null: false
      t.string :expected_state_digest, null: false
      t.json :preview, null: false, default: {}
      t.string :confirmation_nonce, null: false
      t.string :confirmation_digest, null: false
      t.string :idempotency_key, null: false
      t.datetime :deadline_at, null: false
      t.datetime :approved_at
      t.datetime :executed_at
      t.datetime :terminal_at
      t.text :failure_reason
      t.timestamps

      t.index :confirmation_digest, unique: true
      t.index :confirmation_nonce, unique: true
      t.index %i[agent_session_id idempotency_key], unique: true, name: "index_agent_mutation_proposals_on_session_and_idempotency"
      t.index %i[conversation_id status], name: "index_agent_mutation_proposals_on_conversation_and_status"
      t.check_constraint "status IN ('pending', 'approved', 'denied', 'cancelled', 'expired', 'executed', 'failed')", name: "agent_mutation_proposals_status"
    end

    create_table :agent_mutation_executions do |t|
      t.references :mutation_proposal, null: false, foreign_key: { to_table: :agent_mutation_proposals }, index: { unique: true }
      t.references :executed_by, foreign_key: { to_table: :users }
      t.string :operation, null: false
      t.string :idempotency_key, null: false
      t.string :input_digest, null: false
      t.json :before_state, null: false, default: {}
      t.json :after_state, null: false, default: {}
      t.json :result, null: false, default: {}
      t.string :outcome, null: false
      t.datetime :executed_at, null: false
      t.timestamps

      t.check_constraint "outcome = 'succeeded'", name: "agent_mutation_executions_outcome"
    end

    add_column :agent_permission_requests, :deadline_at, :datetime
    add_column :agent_permission_requests, :terminal_at, :datetime
    add_column :agent_permission_requests, :mutation_proposal_id, :integer
    add_index :agent_permission_requests, :mutation_proposal_id, unique: true
    add_foreign_key :agent_permission_requests, :agent_mutation_proposals, column: :mutation_proposal_id
    remove_check_constraint :agent_permission_requests,
      "status IN ('pending', 'approved', 'denied', 'cancelled')",
      name: "agent_permission_requests_status"
    add_check_constraint :agent_permission_requests,
      "status IN ('pending', 'approved', 'denied', 'cancelled', 'expired')",
      name: "agent_permission_requests_status"
  end
end
