require "digest"
require "securerandom"

class Agent::Grant < ApplicationRecord
  include Agent::Contextual

  CAPABILITY_GROUPS = {
    "health_read" => %w[ health.read ],
    "health_write" => %w[ health.write ]
  }.freeze

  belongs_to :household
  belongs_to :person
  belongs_to :conversation, class_name: "Agent::Conversation"
  belongs_to :agent_session, class_name: "Agent::Session"
  belongs_to :browser_session, class_name: "::Session", optional: true
  belongs_to :issued_by, class_name: "User"

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
  validates :browser_session, presence: true, on: :create

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

      Agent::Grant::Credential.new(grant: grant, bearer: "#{locator}.#{secret}")
    end

    def verify(bearer:, browser_session:, conversation:, agent_session:, capability:, at: Time.current)
      locator, secret = bearer.to_s.split(".", 2)
      return unless locator.present? && secret.present?

      grant = active_at(at).find_by(token_locator: locator)
      return unless grant&.secret_matches?(secret)
      return unless grant.browser_session_id == browser_session.id
      return unless grant.conversation_id == conversation.id
      return unless grant.agent_session_id == agent_session.id
      return unless grant.household_id == conversation.household_id && grant.person_id == conversation.person_id
      return unless grant.allows_capability?(capability)

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
    return self if revoked_at?

    update!(revoked_at: Time.current, revocation_reason: reason)
    Agent::AuditEvent.record!(
      subject: self,
      event_type: "grant.revoked",
      actor: by,
      outcome: "revoked",
      metadata: { "reason" => reason }
    )
    self
  end

  def secret_matches?(secret)
    candidate = Digest::SHA256.hexdigest(secret)
    ActiveSupport::SecurityUtils.fixed_length_secure_compare(token_digest, candidate)
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
end
