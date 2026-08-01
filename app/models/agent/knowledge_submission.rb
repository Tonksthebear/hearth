require "digest"

class Agent::KnowledgeSubmission < ApplicationRecord
  include Agent::Contextual

  class IdempotencyConflict < ArgumentError; end

  STATUSES = %w[ pending accepted materialized admitted processing complete failed unavailable ].freeze
  TERMINAL_STATUSES = %w[ complete failed unavailable ].freeze
  DISPATCH_CLAIM_TTL = 30.seconds
  ORIGIN = "hearth_agent"

  belongs_to :household
  belongs_to :person
  belongs_to :conversation, class_name: "Agent::Conversation"
  belongs_to :agent_session, class_name: "Agent::Session"
  belongs_to :agent_grant, class_name: "Agent::Grant"
  belongs_to :message, class_name: "Agent::Message"
  has_one :permission_request,
    as: :permission_subject,
    class_name: "Agent::PermissionRequest",
    dependent: :restrict_with_exception

  validates :request_id, :origin, :requested_intent, :content, :content_digest, :content_preview, presence: true
  validates :request_id, uniqueness: { scope: :agent_session_id }, length: { maximum: 128 }
  validates :origin, length: { maximum: 64 }
  validates :requested_intent, length: { maximum: 64 }
  validates :content, length: { maximum: 65_536 }
  validates :status, inclusion: { in: STATUSES }
  validate :exact_context

  class << self
    def propose!(grant:, message:, content:, requested_intent:, request_id:, deadline_at:)
      existing = find_by(agent_session: grant.agent_session, request_id: request_id)
      redactor = Redactor.new(household: grant.household)
      redacted_content = redactor.redact(content)
      digest = Digest::SHA256.hexdigest(redacted_content)
      if existing
        unless existing.message_id == message.id && existing.requested_intent == requested_intent &&
            ActiveSupport::SecurityUtils.secure_compare(existing.content_digest, digest)
          raise IdempotencyConflict, "Idempotency key was reused with different knowledge content or intent"
        end
        existing.dispatch_approved_subject! if existing.permission_request&.status == "approved"
        return existing
      end

      transaction do
        submission = create!(
          household: grant.household,
          person: grant.person,
          conversation: grant.conversation,
          agent_session: grant.agent_session,
          agent_grant: grant,
          message: message,
          request_id: request_id,
          origin: ORIGIN,
          requested_intent: requested_intent,
          content: redacted_content,
          content_digest: digest,
          content_preview: redactor.preview(redacted_content)
        )
        Agent::PermissionRequest.create!(
          household: submission.household,
          person: submission.person,
          conversation: submission.conversation,
          agent_session: submission.agent_session,
          permission_subject: submission,
          external_request_id: "knowledge-#{submission.id}",
          tool_name: "knowledge.inbox.submit",
          capability: "knowledge.submit",
          input_body: JSON.generate(
            message_id: message.id,
            requested_intent: requested_intent,
            content_digest: digest,
            request_id: request_id
          ),
          input_digest: digest,
          deadline_at: deadline_at
        )
        Agent::AuditEvent.record!(
          subject: submission,
          event_type: "knowledge.submission_proposed",
          actor: grant.issued_by,
          outcome: "pending",
          body_digest: digest,
          metadata: { "request_id" => request_id }
        )
        submission
      end
    rescue ActiveRecord::RecordNotUnique
      retry
    end
  end

  def permission_approved!(permission_request:, actor:)
    raise ArgumentError, "Permission request does not belong to this submission" unless permission_request.permission_subject == self

    dispatch!(actor: actor)
  end

  def dispatch_approved_subject!
    request = permission_request
    return self unless request&.status == "approved"

    dispatch!(actor: request.decision.decided_by)
  end

  def refresh_status!
    return self unless lorester_submission_id.present?
    return self if last_polled_at && last_polled_at > 1.second.ago

    response = Lorester::Client.new.submission_status(lorester_submission_id)
    apply_lorester_status!(response.merge("polled_at" => Time.current))
  end

  def terminal? = status.in?(TERMINAL_STATUSES)

  private
    def dispatch!(actor:)
      return self unless claim_dispatch!

      response = Lorester::Client.new.submit(
        request_id: request_id,
        origin: origin,
        content: content,
        conversation_reference: "hearth-conversation-#{conversation_id}",
        message_reference: "hearth-message-#{message_id}",
        requested_intent: requested_intent
      )
      apply_lorester_status!(response)
      Agent::AuditEvent.record!(
        subject: self,
        event_type: "knowledge.submission_dispatched",
        actor: actor,
        outcome: status,
        body_digest: content_digest,
        metadata: { "request_id" => request_id, "submission_id" => lorester_submission_id, "state" => status }.compact
      )
      self
    rescue Lorester::Client::Error => error
      update!(diagnostic: error.code, dispatched_at: nil)
      Agent::AuditEvent.record!(
        subject: self,
        event_type: "knowledge.submission_failed",
        actor: actor,
        outcome: "failed",
        body_digest: content_digest,
        metadata: { "request_id" => request_id, "diagnostic" => error.code }
      )
      raise
    end

    def claim_dispatch!
      claimed_at = Time.current
      claimed = self.class
        .where(id: id, lorester_submission_id: nil)
        .where.not(status: TERMINAL_STATUSES)
        .where("dispatched_at IS NULL OR dispatched_at <= ?", claimed_at - DISPATCH_CLAIM_TTL)
        .update_all(dispatched_at: claimed_at)
      reload if claimed == 1
      claimed == 1
    end

    def apply_lorester_status!(response)
      attributes = {
        lorester_submission_id: response.fetch("submission_id"),
        status: response.fetch("state"),
        diagnostic: response["diagnostic"],
        dispatched_at: dispatched_at || Time.current,
        provenance: {
          "contract_version" => Lorester::Client::CONTRACT_VERSION,
          "submission_id" => response.fetch("submission_id"),
          "updated_at" => response.fetch("updated_at")
        },
        terminal_at: response.fetch("state").in?(TERMINAL_STATUSES) ? (terminal_at || Time.current) : terminal_at
      }
      attributes[:last_polled_at] = response["polled_at"] if response["polled_at"]
      update!(attributes)
    end

    def exact_context
      return unless agent_grant && message
      errors.add(:base, "must use the exact ACP grant context") unless
        agent_grant.household_id == household_id && agent_grant.person_id == person_id &&
        agent_grant.conversation_id == conversation_id && agent_grant.agent_session_id == agent_session_id
      errors.add(:message, "must belong to the exact conversation context") unless
        message.household_id == household_id && message.person_id == person_id &&
        message.conversation_id == conversation_id &&
        (message.agent_session_id.nil? || message.agent_session_id == agent_session_id)
    end
end
