class AddWebAgentSetup < ActiveRecord::Migration[8.1]
  CERTIFIED_PROFILES = {
    "grok" => "Grok Build",
    "codex" => "Codex ACP adapter",
    "claude" => "Claude ACP wrapper"
  }.freeze

  def change
    add_column :agent_profiles, :certified_key, :string
    reversible do |direction|
      direction.up do
        CERTIFIED_PROFILES.each do |key, name|
          execute <<~SQL.squish
            UPDATE agent_profiles
            SET certified_key = #{connection.quote(key)}
            WHERE certified_key IS NULL AND name = #{connection.quote(name)}
          SQL
        end
      end
    end
    add_index :agent_profiles, %i[ household_id certified_key ], unique: true,
      where: "certified_key IS NOT NULL",
      name: "index_agent_profiles_on_household_and_certified_key"

    create_table :agent_setup_requests do |t|
      t.references :household, null: false, foreign_key: true
      t.references :requested_by, foreign_key: { to_table: :users }
      t.string :certified_key, null: false
      t.string :action, null: false
      t.string :authentication_method_id
      t.string :idempotency_key, null: false
      t.string :origin, null: false
      t.string :status, null: false, default: "pending"
      t.boolean :cli_available
      t.string :cli_version
      t.boolean :adapter_available
      t.string :adapter_version
      t.string :error_category
      t.string :error_message
      t.string :claimed_by
      t.datetime :claimed_at
      t.datetime :dispatched_at
      t.datetime :heartbeat_at
      t.datetime :lease_expires_at
      t.datetime :completed_at
      t.datetime :cancel_requested_at
      t.timestamps
    end
    add_index :agent_setup_requests, %i[ household_id idempotency_key ], unique: true,
      name: "index_agent_setup_requests_on_household_and_idempotency"
    add_index :agent_setup_requests, %i[ status created_at ]
    add_check_constraint :agent_setup_requests,
      "action IN ('detect', 'enable', 'authenticate', 'reauthenticate', 'disable')",
      name: "agent_setup_requests_action"
    add_check_constraint :agent_setup_requests,
      "origin IN ('web', 'cli')",
      name: "agent_setup_requests_origin"
    add_check_constraint :agent_setup_requests,
      "status IN ('pending', 'running', 'succeeded', 'failed', 'cancelled', 'expired')",
      name: "agent_setup_requests_status"

    create_table :agent_runtime_statuses do |t|
      t.references :household, null: false, foreign_key: true, index: { unique: true }
      t.string :owner, null: false
      t.string :status, null: false, default: "online"
      t.string :failure_category
      t.datetime :started_at, null: false
      t.datetime :heartbeat_at, null: false
      t.datetime :stopped_at
      t.timestamps
    end
    add_check_constraint :agent_runtime_statuses,
      "status IN ('online', 'stopped', 'failed')",
      name: "agent_runtime_statuses_status"
  end
end
