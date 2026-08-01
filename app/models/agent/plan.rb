class Agent::Plan < ApplicationRecord
  include Agent::Contextual

  belongs_to :household
  belongs_to :person
  belongs_to :conversation, class_name: "Agent::Conversation"
  belongs_to :agent_session, class_name: "Agent::Session"

  validates :conversation_id, uniqueness: true
  validate :entries_are_a_list

  after_commit :broadcast_plan

  private
    def entries_are_a_list
      errors.add(:entries, "must be a list") unless entries.is_a?(Array)
    end

    def broadcast_plan
      broadcast_replace_to conversation,
        target: "agent_plan",
        partial: "agent/conversations/plan",
        locals: { plan: self }
    end
end
