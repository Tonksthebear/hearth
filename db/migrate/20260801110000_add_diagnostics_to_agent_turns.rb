class AddDiagnosticsToAgentTurns < ActiveRecord::Migration[8.1]
  def change
    add_column :agent_turns, :warning_message, :string
    add_column :agent_turns, :dropped_event_count, :integer, null: false, default: 0
    add_check_constraint :agent_turns, "dropped_event_count >= 0", name: "agent_turns_dropped_event_count"
  end
end
