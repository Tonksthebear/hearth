class AllowStartingAgentRuntimeStatus < ActiveRecord::Migration[8.1]
  def up
    remove_check_constraint :agent_runtime_statuses, name: "agent_runtime_statuses_status"
    add_check_constraint :agent_runtime_statuses,
      "status IN ('starting', 'online', 'stopped', 'failed')",
      name: "agent_runtime_statuses_status"
  end

  def down
    execute "UPDATE agent_runtime_statuses SET status = 'failed', failure_category = 'migration_rollback' WHERE status = 'starting'"
    remove_check_constraint :agent_runtime_statuses, name: "agent_runtime_statuses_status"
    add_check_constraint :agent_runtime_statuses,
      "status IN ('online', 'stopped', 'failed')",
      name: "agent_runtime_statuses_status"
  end
end
