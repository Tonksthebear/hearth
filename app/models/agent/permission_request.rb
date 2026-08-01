class Agent::PermissionRequest < ApplicationRecord
  include Agent::Contextual
  include Agent::Redactable

  STATUSES = %w[ pending approved denied cancelled expired ].freeze

  belongs_to :household
  belongs_to :person
  belongs_to :conversation, class_name: "Agent::Conversation"
  belongs_to :agent_session, class_name: "Agent::Session"
  belongs_to :redacted_by, class_name: "User", optional: true
  belongs_to :permission_subject, polymorphic: true, optional: true
  has_one :decision, class_name: "Agent::PermissionDecision", dependent: :restrict_with_exception

  validates :external_request_id, :tool_name, :capability, presence: true
  validates :external_request_id, uniqueness: { scope: :agent_session_id }
  validates :status, inclusion: { in: STATUSES }
  validates :input_body, presence: true, unless: :redacted_at?
  validates :input_digest, presence: true
  validates :permission_subject_type,
    inclusion: { in: %w[Agent::MutationProposal Agent::KnowledgeSubmission] },
    allow_nil: true
  validates :deadline_at, presence: true, if: :permission_subject
  validate :permission_subject_matches_context

  after_update_commit :dispatch_approved_subject!, if: :approved_status_committed?

  def decide!(outcome:, by:, reason: nil)
    expired = false
    with_lock do
      if deadline_at && deadline_at <= Time.current
        expire_without_lock!(reason: "permission deadline passed") if status == "pending"
        expired = true
        next
      end
      unless status == "pending" && %w[ approved denied ].include?(outcome.to_s)
        errors.add(:status, "can only be decided once")
        raise ActiveRecord::RecordInvalid, self
      end

      create_decision!(outcome: outcome, decided_by: by, reason: reason)
      update!(status: outcome, terminal_at: Time.current)
      audit!("permission.#{outcome}", actor: by, outcome: outcome)
    end
    if expired
      errors.add(:status, "permission deadline passed")
      raise ActiveRecord::RecordInvalid, self
    end
    decision
  end

  def cancel!(reason: nil)
    with_lock do
      unless status == "pending"
        errors.add(:status, "can only cancel a pending request")
        raise ActiveRecord::RecordInvalid, self
      end

      update!(status: "cancelled", terminal_at: Time.current)
      audit!("permission.cancelled", outcome: "cancelled", reason: reason)
    end
    self
  end

  def expire!(reason: "permission deadline passed")
    with_lock do
      unless status == "pending"
        errors.add(:status, "can only expire a pending request")
        raise ActiveRecord::RecordInvalid, self
      end
      expire_without_lock!(reason: reason)
    end
    self
  end

  def expire_if_needed!
    expired = false
    with_lock do
      if status == "pending" && deadline_at && deadline_at <= Time.current
        expire_without_lock!(reason: "permission deadline passed")
        expired = true
      end
    end
    expired
  end

  private
    def approved_status_committed?
      saved_change_to_status? && status == "approved" && permission_subject.present?
    end

    def dispatch_approved_subject!
      permission_subject.permission_approved!(permission_request: self, actor: decision.decided_by)
    end

    def expire_without_lock!(reason:)
      update!(status: "expired", terminal_at: Time.current)
      audit!("permission.expired", outcome: "expired", reason: reason)
    end

    def audit!(event_type, actor: nil, outcome:, reason: nil)
      Agent::AuditEvent.record!(
        subject: self,
        event_type: event_type,
        actor: actor,
        outcome: outcome,
        body_digest: input_digest,
        metadata: { "tool_name" => tool_name, "capability" => capability, "reason" => reason }.compact
      )
    end

    def permission_subject_matches_context
      return unless permission_subject
      return unless permission_subject_type.in?(%w[Agent::MutationProposal Agent::KnowledgeSubmission])
      errors.add(:permission_subject, "must match the exact ACP context") unless
        permission_subject.household_id == household_id && permission_subject.person_id == person_id &&
        permission_subject.conversation_id == conversation_id && permission_subject.agent_session_id == agent_session_id
    end

    def sensitive_body_columns = %i[ input_body ]
end
