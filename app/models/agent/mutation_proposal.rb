require "digest"
require "json"
require "securerandom"

class Agent::MutationProposal < ApplicationRecord
  include Agent::Contextual

  STATUSES = %w[ pending approved denied cancelled expired executed failed ].freeze

  belongs_to :household
  belongs_to :person
  belongs_to :conversation, class_name: "Agent::Conversation"
  belongs_to :agent_session, class_name: "Agent::Session"
  belongs_to :agent_grant, class_name: "Agent::Grant"
  belongs_to :requested_by, class_name: "User", optional: true
  belongs_to :approved_by, class_name: "User", optional: true
  belongs_to :executed_by, class_name: "User", optional: true
  has_one :execution, class_name: "Agent::MutationExecution", dependent: :restrict_with_exception
  has_one :permission_request, class_name: "Agent::PermissionRequest", dependent: :restrict_with_exception

  validates :operation, :input_body, :input_digest, :expected_state_digest,
    :confirmation_nonce, :confirmation_digest, :idempotency_key, :deadline_at, presence: true
  validates :status, inclusion: { in: STATUSES }
  validate :exact_context

  scope :pending, -> { where(status: "pending") }

  before_validation :prepare_confirmation, on: :create

  class << self
    def propose!(grant:, operation:, arguments:, preview:, expected_state:, idempotency_key:, deadline_at:)
      input_body = JSON.generate(arguments.deep_stringify_keys)
      input_digest = input_digest_for(arguments)
      existing = find_by(agent_session: grant.agent_session, idempotency_key: idempotency_key)
      if existing
        raise ArgumentError, "Idempotency key was reused with different input" unless existing.input_digest == input_digest
        return [ existing, nil ]
      end

      proposal = create!(
        household: grant.household,
        person: grant.person,
        conversation: grant.conversation,
        agent_session: grant.agent_session,
        agent_grant: grant,
        requested_by: grant.issued_by,
        operation: operation,
        input_body: input_body,
        input_digest: input_digest,
        expected_state_digest: Digest::SHA256.hexdigest(JSON.generate(expected_state)),
        preview: preview,
        idempotency_key: idempotency_key,
        deadline_at: deadline_at
      )
      Agent::AuditEvent.record!(
        subject: proposal,
        event_type: "mutation.proposed",
        actor: proposal.requested_by,
        outcome: "pending",
        body_digest: input_digest,
        metadata: { "operation" => operation }
      )
      Agent::PermissionRequest.create!(
        household: grant.household,
        person: grant.person,
        conversation: grant.conversation,
        agent_session: grant.agent_session,
        mutation_proposal: proposal,
        external_request_id: "mutation-#{proposal.id}",
        tool_name: operation,
        capability: "health.write",
        input_body: input_body,
        input_digest: input_digest,
        deadline_at: deadline_at
      )
      [ proposal, proposal.confirmation_token ]
    rescue ActiveRecord::RecordNotUnique
      retry
    end

    def execute_immediate!(grant:, operation:, arguments:, expected_state:, idempotency_key:)
      input_body = JSON.generate(arguments.deep_stringify_keys)
      input_digest = input_digest_for(arguments)
      existing = find_by(agent_session: grant.agent_session, idempotency_key: idempotency_key)
      if existing
        raise ArgumentError, "Idempotency key was reused with different input" unless existing.input_digest == input_digest
        return existing.execution if existing.execution
        raise ArgumentError, "Idempotency key belongs to an unfinished mutation"
      end

      proposal = create!(
        household: grant.household, person: grant.person, conversation: grant.conversation,
        agent_session: grant.agent_session, agent_grant: grant, requested_by: grant.issued_by,
        operation: operation, status: "approved", input_body: input_body, input_digest: input_digest,
        expected_state_digest: Digest::SHA256.hexdigest(JSON.generate(expected_state)),
        preview: {},
        idempotency_key: idempotency_key, deadline_at: [ grant.expires_at, Time.current + 1.minute ].min,
        approved_by: grant.issued_by, approved_at: Time.current
      )
      proposal.execute!(by: grant.issued_by)
    rescue ActiveRecord::RecordNotUnique
      retry
    end

    def input_digest_for(arguments)
      Digest::SHA256.hexdigest(JSON.generate(canonicalize(arguments.deep_stringify_keys)))
    end

    private
      def canonicalize(value)
        case value
        when Hash then value.keys.sort.to_h { |key| [ key, canonicalize(value.fetch(key)) ] }
        when Array then value.map { |item| canonicalize(item) }
        else value
        end
      end
  end

  def arguments = JSON.parse(input_body)

  def confirmation_token
    self.class.confirmation_verifier.generate(
      confirmation_payload,
      purpose: "agent_mutation_confirmation",
      expires_at: deadline_at
    )
  end

  def self.confirmation_verifier
    Rails.application.message_verifier("agent_mutation_confirmation")
  end

  def decide!(outcome:, by:, token: nil, reason: nil)
    expired = false
    approved = false
    with_lock do
      if deadline_at <= Time.current
        update!(status: "expired", terminal_at: Time.current, failure_reason: "confirmation deadline passed")
        permission_request&.expire!(reason: "confirmation deadline passed") if permission_request&.status == "pending"
        audit!("mutation.expired", by: by, outcome: "expired")
        expired = true
        next
      end
      raise ActiveRecord::RecordInvalid, self unless status == "pending"
      unless %w[ approved denied ].include?(outcome.to_s)
        errors.add(:status, "must be approved or denied")
        raise ActiveRecord::RecordInvalid, self
      end
      verify_token!(token)
      update!(
        status: outcome,
        approved_by: by,
        approved_at: Time.current,
        terminal_at: outcome.to_s == "denied" ? Time.current : nil,
        failure_reason: reason
      )
      permission_request&.decide!(outcome: outcome, by: by, reason: reason) if permission_request&.status == "pending"
      audit!("mutation.#{outcome}", by: by, outcome: outcome)
      approved = outcome.to_s == "approved"
    end
    if expired
      errors.add(:status, "confirmation deadline passed")
      raise ActiveRecord::RecordInvalid, self
    end
    approved ? execute!(by: by) : self
  ensure
    broadcast_confirmation
    broadcast_permission_status if persisted? && status != "pending"
  end

  def cancel!(reason:, by: nil, status: "cancelled")
    with_lock do
      return self if terminal?
      update!(status: status, terminal_at: Time.current, failure_reason: reason)
      if permission_request&.status == "pending"
        status == "expired" ? permission_request.expire!(reason: reason) : permission_request.cancel!(reason: reason)
      end
      audit!("mutation.#{status}", by: by, outcome: status)
    end
    broadcast_confirmation
    broadcast_permission_status
    self
  end

  def execute!(by:)
    return execution if execution
    raise ActiveRecord::RecordInvalid, self unless status == "approved"

    transaction do
      with_lock do
        return execution if execution
        raise ActiveRecord::RecordInvalid, self unless status == "approved"
        raise Agent::Grant::AuthorizationRequired, "The staged operational grant is no longer active" unless staged_grant_active?
        raise ActiveRecord::StaleObjectError.new(self, "execute") unless current_expected_state_digest == expected_state_digest

        result = Agent::Mutation::Operations.execute!(operation: operation, arguments: arguments, proposal: self)
        create_execution!(
          executed_by: by,
          operation: operation,
          idempotency_key: idempotency_key,
          input_digest: input_digest,
          before_state: result.fetch(:before),
          after_state: result.fetch(:after),
          result: result.fetch(:result),
          outcome: "succeeded",
          executed_at: Time.current
        )
        update!(status: "executed", executed_by: by, executed_at: Time.current, terminal_at: Time.current)
        audit!("mutation.executed", by: by, outcome: "executed")
        execution
      end
    end
  rescue StandardError => error
    reload
    unless terminal?
      update!(status: "failed", executed_by: by, terminal_at: Time.current, failure_reason: stable_failure_reason(error))
      audit!("mutation.failed", by: by, outcome: "failed")
    end
    raise
  ensure
    broadcast_permission_status if persisted? && terminal?
  end

  def expire_if_needed!
    cancel!(reason: "confirmation deadline passed", status: "expired") if status == "pending" && deadline_at <= Time.current
  end

  def terminal? = status.in?(%w[ denied cancelled expired executed failed ])

  def pending_confirmation? = status == "pending" && deadline_at > Time.current

  def permission_channel = "agent_mutation_permission_#{id}"

  def broadcast_permission_status
    ActionCable.server.broadcast(permission_channel, { proposal_id: id, status: status })
  end

  def current_expected_state_digest
    Digest::SHA256.hexdigest(JSON.generate(Agent::Mutation::Operations.expected_state(operation: operation, arguments: arguments, proposal: self)))
  end

  def broadcast_confirmation(token = nil)
    token ||= confirmation_token if status == "pending"
    Turbo::StreamsChannel.broadcast_replace_to(
      conversation,
      target: "agent_confirmation_center",
      partial: "agent/mutation_proposals/center",
      locals: { proposal: self, confirmation_token: token }
    )
  end

  private
    def verify_token!(token)
      candidate = Digest::SHA256.hexdigest(token.to_s)
      verified = self.class.confirmation_verifier.verified(token, purpose: "agent_mutation_confirmation")
      return if token.present? &&
        ActiveSupport::SecurityUtils.secure_compare(confirmation_digest, candidate) &&
        verified == confirmation_payload

      errors.add(:base, "confirmation token is invalid or unavailable")
      raise ActiveRecord::RecordInvalid, self
    end

    def prepare_confirmation
      self.confirmation_nonce ||= SecureRandom.hex(24)
      self.confirmation_digest = Digest::SHA256.hexdigest(confirmation_token)
    end

    def confirmation_payload
      {
        "nonce" => confirmation_nonce,
        "agent_session_id" => agent_session_id,
        "operation" => operation,
        "deadline_at" => deadline_at&.utc&.iso8601(6)
      }
    end

    def exact_context
      return unless agent_session && conversation
      errors.add(:base, "must use the exact ACP context") unless
        agent_session.household_id == household_id && agent_session.person_id == person_id &&
        agent_session.conversation_id == conversation_id &&
        agent_grant&.agent_session_id == agent_session_id &&
        agent_grant&.household_id == household_id && agent_grant&.person_id == person_id &&
        agent_grant&.conversation_id == conversation_id
    end

    def staged_grant_active?
      agent_grant.revoked_at.nil? && agent_grant.expires_at > Time.current &&
        agent_grant.allows_capability?("health.write") &&
        agent_session.active_operational_authorization.present?
    end

    def stable_failure_reason(error)
      case error
      when ActiveRecord::StaleObjectError then "previewed state changed before execution"
      when Agent::Grant::AuthorizationRequired then error.message
      when Agent::Mutation::Operations::Prohibited, ArgumentError then error.message.first(500)
      else "mutation execution failed"
      end
    end

    def audit!(event_type, by:, outcome:)
      Agent::AuditEvent.record!(
        subject: self, event_type: event_type, actor: by, outcome: outcome,
        body_digest: input_digest, metadata: { "operation" => operation }
      )
    end
end
