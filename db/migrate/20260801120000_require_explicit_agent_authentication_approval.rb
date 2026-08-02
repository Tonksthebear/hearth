class RequireExplicitAgentAuthenticationApproval < ActiveRecord::Migration[8.1]
  def change
    remove_check_constraint :agent_installations, name: "agent_installations_authentication_status"
    add_check_constraint :agent_installations,
      "authentication_status IN ('unknown', 'not_required', 'required', 'authenticated', 'failed')",
      name: "agent_installations_authentication_status"

    remove_check_constraint :agent_sessions, name: "agent_sessions_authentication_status"
    add_check_constraint :agent_sessions,
      "authentication_status IN ('unknown', 'not_required', 'required', 'authenticated', 'failed')",
      name: "agent_sessions_authentication_status"

    add_column :agent_installations, :authentication_method_id, :string
    add_column :agent_installations, :authentication_approved_at, :datetime
    add_column :agent_installations, :authentication_origin, :string
  end
end
