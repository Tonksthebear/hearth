class AddDurableAgentTurnsAndChatProjections < ActiveRecord::Migration[8.1]
  def change
    create_table :agent_turns do |t|
      t.references :household, null: false, foreign_key: true
      t.references :person, null: false, foreign_key: true
      t.references :conversation, null: false, foreign_key: { to_table: :agent_conversations }
      t.references :agent_session, foreign_key: { to_table: :agent_sessions }
      t.references :browser_session, null: false, foreign_key: { to_table: :sessions, on_delete: :cascade }
      t.references :user_message, null: false, foreign_key: { to_table: :agent_messages }
      t.string :idempotency_key, null: false
      t.string :status, null: false, default: "pending"
      t.string :claimed_by
      t.datetime :claimed_at
      t.datetime :lease_expires_at
      t.datetime :heartbeat_at
      t.datetime :dispatched_at
      t.datetime :cancel_requested_at
      t.datetime :cancel_sent_at
      t.datetime :completed_at
      t.string :stop_reason
      t.string :error_message
      t.timestamps
    end
    add_index :agent_turns, %i[ browser_session_id idempotency_key ], unique: true
    add_index :agent_turns, %i[ status lease_expires_at ]
    add_index :agent_turns, %i[ conversation_id created_at ]
    add_check_constraint :agent_turns,
      "status IN ('pending', 'claimed', 'running', 'succeeded', 'failed', 'cancelled')",
      name: "agent_turns_status"

    create_table :agent_plans do |t|
      t.references :household, null: false, foreign_key: true
      t.references :person, null: false, foreign_key: true
      t.references :conversation, null: false, foreign_key: { to_table: :agent_conversations }, index: { unique: true }
      t.references :agent_session, null: false, foreign_key: { to_table: :agent_sessions }
      t.json :entries, null: false, default: []
      t.timestamps
    end

    create_table :agent_citations do |t|
      t.references :household, null: false, foreign_key: true
      t.references :person, null: false, foreign_key: true
      t.references :conversation, null: false, foreign_key: { to_table: :agent_conversations }
      t.references :agent_session, null: false, foreign_key: { to_table: :agent_sessions }
      t.references :message, foreign_key: { to_table: :agent_messages }
      t.string :external_id, null: false
      t.string :title, null: false
      t.string :url
      t.string :source_kind, null: false, default: "external_search"
      t.timestamps
    end
    add_index :agent_citations, %i[ agent_session_id external_id ], unique: true
    add_index :agent_citations, %i[ conversation_id created_at ]
    add_check_constraint :agent_citations,
      "source_kind IN ('hearth_fact', 'vault_knowledge', 'external_search', 'agent_suggestion')",
      name: "agent_citations_source_kind"

    add_column :agent_messages, :source_kind, :string, null: false, default: "hearth_fact"
    add_column :agent_messages, :provenance, :json, null: false, default: {}
    add_check_constraint :agent_messages,
      "source_kind IN ('hearth_fact', 'vault_knowledge', 'external_search', 'agent_suggestion')",
      name: "agent_messages_source_kind"

    change_column_null :agent_tool_activities, :tool_name, true
    add_column :agent_tool_activities, :source, :string, null: false, default: "mcp"
    add_column :agent_tool_activities, :display_title, :string
    add_column :agent_tool_activities, :kind, :string
    add_check_constraint :agent_tool_activities,
      "source IN ('mcp', 'acp')",
      name: "agent_tool_activities_source"
    add_check_constraint :agent_tool_activities,
      "(source = 'mcp' AND tool_name IS NOT NULL) OR (source = 'acp' AND display_title IS NOT NULL AND kind IS NOT NULL)",
      name: "agent_tool_activities_source_shape"
  end
end
