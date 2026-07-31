class CreateAgentDomain < ActiveRecord::Migration[8.1]
  def change
    create_table :agent_profiles do |t|
      t.references :household, null: false, foreign_key: true
      t.string :name, null: false
      t.text :launch_command, null: false
      t.string :working_directory
      t.json :environment_keys, null: false, default: []
      t.boolean :enabled, null: false, default: true
      t.timestamps
    end
    add_index :agent_profiles, %i[ household_id name ], unique: true

    create_table :agent_installations do |t|
      t.references :household, null: false, foreign_key: true
      t.references :profile, null: false, foreign_key: { to_table: :agent_profiles }
      t.string :external_id, null: false
      t.string :executable_path, null: false
      t.integer :protocol_version, null: false
      t.string :status, null: false, default: "observed"
      t.json :advertised_capabilities, null: false, default: {}
      t.json :authentication_methods, null: false, default: []
      t.string :authentication_status, null: false, default: "unknown"
      t.datetime :last_seen_at
      t.timestamps
    end
    add_index :agent_installations, %i[ household_id external_id ], unique: true
    add_check_constraint :agent_installations, "protocol_version > 0", name: "agent_installations_positive_protocol"
    add_check_constraint :agent_installations,
      "status IN ('observed', 'available', 'unavailable')",
      name: "agent_installations_status"
    add_check_constraint :agent_installations,
      "authentication_status IN ('unknown', 'required', 'authenticated', 'failed')",
      name: "agent_installations_authentication_status"

    create_table :agent_conversations do |t|
      t.references :household, null: false, foreign_key: true
      t.references :person, null: false, foreign_key: true
      t.references :profile, null: false, foreign_key: { to_table: :agent_profiles }
      t.string :title, null: false
      t.string :status, null: false, default: "active"
      t.datetime :closed_at
      t.timestamps
    end
    add_index :agent_conversations, %i[ household_id person_id status ],
      name: "index_agent_conversations_on_context_and_status"
    add_check_constraint :agent_conversations,
      "status IN ('active', 'closed')",
      name: "agent_conversations_status"

    create_table :agent_sessions do |t|
      t.references :household, null: false, foreign_key: true
      t.references :person, null: false, foreign_key: true
      t.references :conversation, null: false, foreign_key: { to_table: :agent_conversations }
      t.references :installation, null: false, foreign_key: { to_table: :agent_installations }
      t.references :browser_session, foreign_key: { to_table: :sessions, on_delete: :nullify }
      t.string :external_session_id, null: false
      t.string :status, null: false, default: "starting"
      t.json :advertised_capabilities, null: false, default: {}
      t.string :authentication_status, null: false, default: "unknown"
      t.datetime :connected_at
      t.datetime :disconnected_at
      t.datetime :closed_at
      t.timestamps
    end
    add_index :agent_sessions, %i[ installation_id external_session_id ], unique: true,
      name: "index_agent_sessions_on_installation_and_external_id"
    add_index :agent_sessions, %i[ conversation_id status ]
    add_check_constraint :agent_sessions,
      "status IN ('starting', 'connected', 'disconnected', 'closed', 'failed')",
      name: "agent_sessions_status"

    create_table :agent_messages do |t|
      t.references :household, null: false, foreign_key: true
      t.references :person, null: false, foreign_key: true
      t.references :conversation, null: false, foreign_key: { to_table: :agent_conversations }
      t.references :agent_session, foreign_key: { to_table: :agent_sessions }
      t.string :external_id
      t.string :role, null: false
      t.text :body
      t.string :body_digest, null: false
      t.datetime :redacted_at
      t.text :redaction_reason
      t.references :redacted_by, foreign_key: { to_table: :users }
      t.timestamps
    end
    add_index :agent_messages, %i[ conversation_id created_at ]
    add_index :agent_messages, %i[ agent_session_id external_id ], unique: true,
      where: "external_id IS NOT NULL",
      name: "index_agent_messages_on_session_and_external_id"
    add_check_constraint :agent_messages,
      "role IN ('user', 'agent', 'system')",
      name: "agent_messages_role"
    add_check_constraint :agent_messages,
      "(body IS NOT NULL AND redacted_at IS NULL) OR (body IS NULL AND redacted_at IS NOT NULL)",
      name: "agent_messages_redaction_state"

    create_table :agent_permission_requests do |t|
      t.references :household, null: false, foreign_key: true
      t.references :person, null: false, foreign_key: true
      t.references :conversation, null: false, foreign_key: { to_table: :agent_conversations }
      t.references :agent_session, null: false, foreign_key: { to_table: :agent_sessions }
      t.string :external_request_id, null: false
      t.string :tool_name, null: false
      t.string :capability, null: false
      t.text :input_body
      t.string :input_digest, null: false
      t.string :status, null: false, default: "pending"
      t.datetime :redacted_at
      t.text :redaction_reason
      t.references :redacted_by, foreign_key: { to_table: :users }
      t.timestamps
    end
    add_index :agent_permission_requests, %i[ agent_session_id external_request_id ], unique: true,
      name: "index_agent_permission_requests_on_session_and_external_id"
    add_index :agent_permission_requests, %i[ conversation_id status ]
    add_check_constraint :agent_permission_requests,
      "status IN ('pending', 'approved', 'denied', 'cancelled')",
      name: "agent_permission_requests_status"
    add_check_constraint :agent_permission_requests,
      "(input_body IS NOT NULL AND redacted_at IS NULL) OR (input_body IS NULL AND redacted_at IS NOT NULL)",
      name: "agent_permission_requests_redaction_state"

    create_table :agent_permission_decisions do |t|
      t.references :permission_request, null: false, foreign_key: { to_table: :agent_permission_requests },
        index: { unique: true }
      t.references :decided_by, null: false, foreign_key: { to_table: :users }
      t.string :outcome, null: false
      t.text :reason
      t.timestamps
    end
    add_check_constraint :agent_permission_decisions,
      "outcome IN ('approved', 'denied')",
      name: "agent_permission_decisions_outcome"

    create_table :agent_tool_activities do |t|
      t.references :household, null: false, foreign_key: true
      t.references :person, null: false, foreign_key: true
      t.references :conversation, null: false, foreign_key: { to_table: :agent_conversations }
      t.references :agent_session, null: false, foreign_key: { to_table: :agent_sessions }
      t.string :external_id
      t.string :tool_name, null: false
      t.string :capability, null: false
      t.string :status, null: false, default: "pending"
      t.text :input_body
      t.string :input_digest, null: false
      t.text :output_body
      t.string :output_digest
      t.integer :output_tokens
      t.datetime :started_at
      t.datetime :completed_at
      t.datetime :redacted_at
      t.text :redaction_reason
      t.references :redacted_by, foreign_key: { to_table: :users }
      t.timestamps
    end
    add_index :agent_tool_activities, %i[ agent_session_id external_id ], unique: true,
      where: "external_id IS NOT NULL",
      name: "index_agent_tool_activities_on_session_and_external_id"
    add_index :agent_tool_activities, %i[ conversation_id created_at ]
    add_check_constraint :agent_tool_activities,
      "status IN ('pending', 'running', 'succeeded', 'failed', 'cancelled')",
      name: "agent_tool_activities_status"
    add_check_constraint :agent_tool_activities,
      "output_tokens IS NULL OR output_tokens >= 0",
      name: "agent_tool_activities_nonnegative_output_tokens"
    add_check_constraint :agent_tool_activities,
      "(input_body IS NOT NULL AND redacted_at IS NULL) OR (input_body IS NULL AND redacted_at IS NOT NULL)",
      name: "agent_tool_activities_redaction_state"

    create_table :agent_grants do |t|
      t.references :household, null: false, foreign_key: true
      t.references :person, null: false, foreign_key: true
      t.references :conversation, null: false, foreign_key: { to_table: :agent_conversations }
      t.references :agent_session, null: false, foreign_key: { to_table: :agent_sessions }
      t.references :browser_session, foreign_key: { to_table: :sessions, on_delete: :nullify }
      t.references :issued_by, null: false, foreign_key: { to_table: :users }
      t.string :token_locator, null: false
      t.string :token_digest, null: false
      t.json :capability_groups, null: false, default: []
      t.integer :calls_limit
      t.integer :calls_used, null: false, default: 0
      t.integer :output_tokens_limit
      t.integer :output_tokens_used, null: false, default: 0
      t.datetime :expires_at, null: false
      t.datetime :revoked_at
      t.text :revocation_reason
      t.timestamps
    end
    add_index :agent_grants, :token_locator, unique: true
    add_index :agent_grants, %i[ browser_session_id revoked_at ]
    add_check_constraint :agent_grants,
      "calls_limit IS NULL OR calls_limit >= 0",
      name: "agent_grants_nonnegative_calls_limit"
    add_check_constraint :agent_grants,
      "calls_used >= 0",
      name: "agent_grants_nonnegative_calls_used"
    add_check_constraint :agent_grants,
      "output_tokens_limit IS NULL OR output_tokens_limit >= 0",
      name: "agent_grants_nonnegative_output_tokens_limit"
    add_check_constraint :agent_grants,
      "output_tokens_used >= 0",
      name: "agent_grants_nonnegative_output_tokens_used"

    create_table :agent_audit_events do |t|
      t.references :household, null: false, foreign_key: true
      t.references :person, null: false, foreign_key: true
      t.references :conversation, null: false, foreign_key: { to_table: :agent_conversations }
      t.references :agent_session, foreign_key: { to_table: :agent_sessions }
      t.references :actor, foreign_key: { to_table: :users }
      t.string :subject_type, null: false
      t.integer :subject_id, null: false
      t.string :event_type, null: false
      t.string :outcome
      t.string :body_digest
      t.json :metadata, null: false, default: {}
      t.timestamps
    end
    add_index :agent_audit_events, %i[ subject_type subject_id ]
    add_index :agent_audit_events, %i[ household_id person_id created_at ],
      name: "index_agent_audit_events_on_context_and_created_at"
    add_index :agent_audit_events, %i[ conversation_id created_at ]
  end
end
