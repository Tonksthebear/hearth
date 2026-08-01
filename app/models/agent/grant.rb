require "digest"
require "securerandom"

class Agent::Grant < ApplicationRecord
  include Agent::Contextual
  class AuthorizationRequired < StandardError; end

  CAPABILITY_GROUPS = {
    "health_read" => %w[ health.read ],
    "health_write" => %w[ health.write ],
    "knowledge_read" => %w[ knowledge.read ],
    "knowledge_submit" => %w[ knowledge.submit ]
  }.freeze

  belongs_to :household
  belongs_to :person
  belongs_to :conversation, class_name: "Agent::Conversation"
  belongs_to :agent_session, class_name: "Agent::Session"
  belongs_to :browser_session, class_name: "::Session", optional: true
  belongs_to :issued_by, class_name: "User", optional: true

  validates :token_locator, :token_digest, presence: true
  validates :token_locator, uniqueness: true
  validates :token_digest, length: { is: 64 }
  validates :calls_limit, :output_tokens_limit,
    numericality: { only_integer: true, greater_than_or_equal_to: 0 },
    allow_nil: true
  validates :calls_used, :output_tokens_used,
    numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :expires_in_future, on: :create
  validate :capability_groups_are_known
  validate :session_context_matches
  validate :authorization_context_is_active, on: :create
  validates :browser_session, presence: true, on: :create, if: :browser_issued?

  RUNTIME_EXPIRES_IN = 15.minutes
  RUNTIME_CALLS_LIMIT = 200
  RUNTIME_OUTPUT_TOKENS_LIMIT = 200_000

  scope :active_at, ->(time = Time.current) { where(revoked_at: nil).where("expires_at > ?", time) }

  class << self
    def capability_groups = CAPABILITY_GROUPS

    def issue!(conversation:, agent_session:, capability_groups:, expires_at:, calls_limit: nil,
      output_tokens_limit: nil)
      household = Current.household
      person = Current.person
      browser_session = Current.session
      raise ArgumentError, "Authenticated household, person, and session are required" unless
        household && person && browser_session

      locator = SecureRandom.hex(16)
      secret = SecureRandom.urlsafe_base64(32)
      transaction do
        grant = create!(
          household: household,
          person: person,
          conversation: conversation,
          agent_session: agent_session,
          browser_session: browser_session,
          issued_by: browser_session.user,
          token_locator: locator,
          token_digest: Digest::SHA256.hexdigest(secret),
          capability_groups: capability_groups,
          expires_at: expires_at,
          calls_limit: calls_limit,
          output_tokens_limit: output_tokens_limit
        )
        Agent::AuditEvent.record!(
          subject: grant,
          event_type: "grant.issued",
          actor: grant.issued_by,
          outcome: "active",
          metadata: { "capability_groups" => grant.capability_groups }
        )
        agent_session.authorize_mcp!

        Agent::Grant::Credential.new(grant: grant, bearer: "#{locator}.#{secret}")
      end
    end

    def verify(bearer:, browser_session:, conversation:, agent_session:, capability:, at: Time.current)
      locator, secret = bearer.to_s.split(".", 2)
      return unless locator.present? && secret.present?
      return unless browser_session && conversation && agent_session

      grant = active_at(at).find_by(token_locator: locator)
      return unless grant&.secret_matches?(secret)
      return unless grant.browser_session_id == browser_session.id
      return unless grant.conversation_id == conversation.id
      return unless grant.agent_session_id == agent_session.id
      return unless grant.household_id == conversation.household_id && grant.person_id == conversation.person_id
      return unless grant.allows_capability?(capability)

      grant
    end

    def issue_runtime!(agent_session:)
      raise ArgumentError, "Persisted starting ACP session is required" unless
        agent_session&.persisted? && agent_session.status == "starting"

      locator = SecureRandom.hex(16)
      secret = SecureRandom.urlsafe_base64(32)
      transaction do
        authorization = agent_session.active_operational_authorization
        capability_groups = %w[ health_read knowledge_read knowledge_submit ]
        capability_groups << "health_write" if authorization
        grant = create!(
          household: agent_session.household,
          person: agent_session.person,
          conversation: agent_session.conversation,
          agent_session: agent_session,
          browser_session: agent_session.browser_session,
          token_locator: locator,
          token_digest: Digest::SHA256.hexdigest(secret),
          capability_groups: capability_groups,
          expires_at: [ RUNTIME_EXPIRES_IN.from_now, authorization&.expires_at ].compact.min,
          calls_limit: RUNTIME_CALLS_LIMIT,
          output_tokens_limit: RUNTIME_OUTPUT_TOKENS_LIMIT
        )
        Agent::AuditEvent.record!(
          subject: grant,
          event_type: "grant.issued",
          outcome: "active",
          metadata: { "capability_groups" => grant.capability_groups, "source" => "acp_runtime" }
        )
        agent_session.authorize_mcp!

        Agent::Grant::Credential.new(grant: grant, bearer: "#{locator}.#{secret}")
      end
    end

    def authenticate(bearer:, at: Time.current)
      locator, secret = bearer.to_s.split(".", 2)
      return unless locator.present? && secret.present?

      grant = includes(:conversation, :agent_session, :browser_session).find_by(token_locator: locator)
      return unless grant&.secret_matches?(secret)
      unless grant.revoked_at.nil? && grant.expires_at > at
        grant.require_session_reauthorization_if_last!(at: at)
        return
      end
      return unless grant.capability_groups.all? { |group| capability_groups.key?(group) }
      return unless grant.conversation&.status == "active"
      return unless grant.agent_session&.status.in?(%w[ starting connected ])
      return unless grant.household_id == grant.conversation.household_id
      return unless grant.person_id == grant.conversation.person_id
      return unless grant.agent_session.conversation_id == grant.conversation_id
      return unless grant.agent_session.household_id == grant.household_id
      return unless grant.agent_session.person_id == grant.person_id
      return unless grant.browser_context_active?
      if grant.calls_limit && grant.calls_used >= grant.calls_limit ||
          grant.output_tokens_limit && grant.output_tokens_used >= grant.output_tokens_limit
        grant.require_session_reauthorization_if_last!(at: at)
        return
      end

      grant
    end
  end

  def allows_capability?(capability)
    resolved = capability_groups.map { |group| self.class.capability_groups[group] }
    resolved.none?(&:nil?) && resolved.flatten.include?(capability)
  end

  def consume(calls: 1, output_tokens: 0, at: Time.current)
    calls = Integer(calls)
    output_tokens = Integer(output_tokens)
    raise ArgumentError, "Usage increments must be nonnegative" if calls.negative? || output_tokens.negative?

    # Returns the guarded UPDATE's affected-row count and does not refresh this instance.
    self.class.active_at(at)
      .where(id: id)
      .where("calls_limit IS NULL OR calls_used + ? <= calls_limit", calls)
      .where("output_tokens_limit IS NULL OR output_tokens_used + ? <= output_tokens_limit", output_tokens)
      .update_all([
        "calls_used = calls_used + ?, output_tokens_used = output_tokens_used + ?, updated_at = ?",
        calls,
        output_tokens,
        Time.current
      ])
  end

  def revoke!(reason:, by: nil)
    raise ArgumentError, "reason is required" if reason.blank?

    transaction do
      revoked_at = Time.current
      revoked = self.class.where(id: id, revoked_at: nil).update_all(
        revoked_at: revoked_at,
        revocation_reason: reason,
        updated_at: revoked_at
      )
      if revoked == 1
        reload
        Agent::AuditEvent.record!(
          subject: self,
          event_type: "grant.revoked",
          actor: by,
          outcome: "revoked",
          metadata: { "reason" => reason }
        )
        agent_session.require_mcp_reauthorization! unless
          self.class.active_at.where(agent_session: agent_session).exists?
      end
    end
    self
  end

  def secret_matches?(secret)
    candidate = Digest::SHA256.hexdigest(secret)
    ActiveSupport::SecurityUtils.fixed_length_secure_compare(token_digest, candidate)
  end

  def browser_issued? = issued_by_id.present?

  def browser_context_active?
    return browser_session_id == agent_session.browser_session_id unless browser_issued?

    agent_session.browser_session_id == browser_session_id && browser_session.present?
  end

  def require_session_reauthorization_if_last!(at: Time.current)
    replacement_exists = self.class.active_at(at)
      .where(agent_session_id: agent_session_id)
      .where.not(id: id)
      .where("calls_limit IS NULL OR calls_used < calls_limit")
      .where("output_tokens_limit IS NULL OR output_tokens_used < output_tokens_limit")
      .exists?
    agent_session.require_mcp_reauthorization! unless replacement_exists
  end

  private
    def expires_in_future
      errors.add(:expires_at, "must be in the future") unless expires_at&.future?
    end

    def capability_groups_are_known
      unknown = capability_groups.reject { |group| self.class.capability_groups.key?(group) }
      errors.add(:capability_groups, "contain unknown groups: #{unknown.join(', ')}") if unknown.any?
    end

    def session_context_matches
      return if agent_session.blank?
      unless agent_session.browser_session_id == browser_session_id
        errors.add(:browser_session, "must match the ACP session")
      end
    end

    def authorization_context_is_active
      errors.add(:conversation, "must be active") unless conversation&.status == "active"
      unless agent_session&.status.in?(%w[ starting connected ])
        errors.add(:agent_session, "must be starting or connected")
      end
    end
end
