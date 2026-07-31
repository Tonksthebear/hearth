class ConstrainAgentSessionAuthenticationStatus < ActiveRecord::Migration[8.1]
  def change
    add_check_constraint :agent_sessions,
      "authentication_status IN ('unknown', 'required', 'authenticated', 'failed')",
      name: "agent_sessions_authentication_status"
  end
end
