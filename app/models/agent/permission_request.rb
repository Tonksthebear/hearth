class Agent::PermissionRequest < ApplicationRecord
  include Agent::Contextual
  include Agent::Redactable

  STATUSES = %w[ pending approved denied cancelled ].freeze

  belongs_to :household
  belongs_to :person
  belongs_to :conversation, class_name: "Agent::Conversation"
  belongs_to :agent_session, class_name: "Agent::Session"
  belongs_to :redacted_by, class_name: "User", optional: true
  has_one :decision, class_name: "Agent::PermissionDecision", dependent: :restrict_with_exception

  validates :external_request_id, :tool_name, :capability, presence: true
  validates :external_request_id, uniqueness: { scope: :agent_session_id }
  validates :status, inclusion: { in: STATUSES }
  validates :input_body, presence: true, unless: :redacted_at?
  validates :input_digest, presence: true

  def decide!(outcome:, by:, reason: nil)
    unless status == "pending" && %w[ approved denied ].include?(outcome.to_s)
      errors.add(:status, "can only be decided once")
      raise ActiveRecord::RecordInvalid, self
    end

    transaction do
      create_decision!(outcome: outcome, decided_by: by, reason: reason)
      update!(status: outcome)
      Agent::AuditEvent.record!(
        subject: self,
        event_type: "permission.#{outcome}",
        actor: by,
        outcome: outcome,
        body_digest: input_digest,
        metadata: { "tool_name" => tool_name, "capability" => capability }
      )
    end
    decision
  end

  def cancel!
    unless status == "pending"
      errors.add(:status, "can only cancel a pending request")
      raise ActiveRecord::RecordInvalid, self
    end

    update!(status: "cancelled")
  end

  private
    def sensitive_body_columns = %i[ input_body ]
end
