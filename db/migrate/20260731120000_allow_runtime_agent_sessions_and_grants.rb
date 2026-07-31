class AllowRuntimeAgentSessionsAndGrants < ActiveRecord::Migration[8.1]
  def change
    change_column_null :agent_sessions, :external_session_id, true
    change_column_null :agent_grants, :issued_by_id, true
  end
end
