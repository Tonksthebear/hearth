require "json"
require "shellwords"

class MakeAgentRuntimeConfigurationRecoveryAndAuthorizationExplicit < ActiveRecord::Migration[8.1]
  def up
    rename_column :agent_profiles, :launch_command, :executable_path
    add_column :agent_profiles, :arguments, :json, null: false, default: []
    split_legacy_launch_commands!
    add_column :agent_profiles, :update_policy, :string, null: false, default: "manual"
    add_check_constraint :agent_profiles,
      "update_policy = 'manual'",
      name: "agent_profiles_manual_update_policy"

    add_column :agent_installations, :agent_version, :string

    add_column :agent_sessions, :recovery_attempts, :integer, null: false, default: 0
    add_column :agent_sessions, :recovery_next_at, :datetime
    add_column :agent_sessions, :recovery_error, :string
    add_column :agent_sessions, :mcp_authorization_status, :string,
      null: false,
      default: "not_configured"
    add_check_constraint :agent_sessions,
      "recovery_attempts >= 0",
      name: "agent_sessions_nonnegative_recovery_attempts"
    add_check_constraint :agent_sessions,
      "mcp_authorization_status IN ('not_configured', 'authorized', 'reauthorization_required')",
      name: "agent_sessions_mcp_authorization_status"

    execute <<~SQL.squish
      UPDATE agent_sessions
      SET mcp_authorization_status = 'authorized'
      WHERE EXISTS (
        SELECT 1
        FROM agent_grants
        WHERE agent_grants.agent_session_id = agent_sessions.id
          AND agent_grants.revoked_at IS NULL
          AND agent_grants.expires_at > CURRENT_TIMESTAMP
      )
    SQL
  end

  def down
    remove_check_constraint :agent_sessions, name: "agent_sessions_mcp_authorization_status"
    remove_check_constraint :agent_sessions, name: "agent_sessions_nonnegative_recovery_attempts"
    remove_columns :agent_sessions,
      :mcp_authorization_status,
      :recovery_error,
      :recovery_next_at,
      :recovery_attempts

    remove_column :agent_installations, :agent_version

    remove_check_constraint :agent_profiles, name: "agent_profiles_manual_update_policy"
    join_explicit_argv!
    remove_columns :agent_profiles, :update_policy, :arguments
    rename_column :agent_profiles, :executable_path, :launch_command
  end

  private
    def split_legacy_launch_commands!
      select_all("SELECT id, executable_path FROM agent_profiles").each do |row|
        argv = Shellwords.split(row.fetch("executable_path"))
        raise "Agent profile #{row.fetch('id')} has an empty launch command" if argv.empty?
        if argv.any? { |argument| argument.match?(/\A(?:\||&&|\|\||;|>|<)\z/) }
          raise "Agent profile #{row.fetch('id')} contains shell operators and cannot be migrated safely"
        end

        executable = argv.shift
        execute <<~SQL.squish
          UPDATE agent_profiles
          SET executable_path = #{connection.quote(executable)},
              arguments = #{connection.quote(JSON.generate(argv))}
          WHERE id = #{connection.quote(row.fetch("id"))}
        SQL
      end
    end

    def join_explicit_argv!
      select_all("SELECT id, executable_path, arguments FROM agent_profiles").each do |row|
        argv = [ row.fetch("executable_path"), *JSON.parse(row.fetch("arguments")) ]
        execute <<~SQL.squish
          UPDATE agent_profiles
          SET executable_path = #{connection.quote(Shellwords.join(argv))}
          WHERE id = #{connection.quote(row.fetch("id"))}
        SQL
      end
    end
end
