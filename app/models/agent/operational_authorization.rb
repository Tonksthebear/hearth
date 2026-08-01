class Agent::OperationalAuthorization < ApplicationRecord
  include Agent::Contextual

  CAPABILITY_GROUPS = %w[ health_write ].freeze

  belongs_to :household
  belongs_to :person
  belongs_to :conversation, class_name: "Agent::Conversation"
  belongs_to :agent_session, class_name: "Agent::Session"
  belongs_to :browser_session, class_name: "::Session", optional: true
  belongs_to :authorized_by, class_name: "User"

  validates :reason, presence: true
  validates :revision, numericality: { only_integer: true, greater_than: 0 }
  validate :capability_groups_are_exact
  validate :exact_context
  validate :expires_in_future, on: :create

  scope :active_at, ->(time = Time.current) { where(revoked_at: nil).where("expires_at > ?", time) }

  class << self
    def authorize!(agent_session:, reason:)
      browser_session = Current.session
      raise ArgumentError, "Authenticated household, person, and session are required" unless
        Current.user && Current.household && Current.person && browser_session

      transaction do
        agent_session.with_lock do
          active_at.where(agent_session: agent_session).find_each do |authorization|
            authorization.revoke!(reason: "operational access replaced", by: Current.user)
          end
          create!(
            household: Current.household,
            person: Current.person,
            conversation: agent_session.conversation,
            agent_session: agent_session,
            browser_session: browser_session,
            authorized_by: Current.user,
            reason: reason,
            authorized_at: Time.current,
            expires_at: Agent::Grant::RUNTIME_EXPIRES_IN.from_now,
            revision: agent_session.operational_authorizations.maximum(:revision).to_i + 1
          ).tap do |authorization|
            Agent::AuditEvent.record!(
              subject: authorization,
              event_type: "operational_authorization.enabled",
              actor: Current.user,
              outcome: "active",
              metadata: { "capability_groups" => authorization.capability_groups, "reason" => reason }
            )
            agent_session.rotate_runtime_authorization!("operational access enabled")
          end
        end
      end
    end
  end

  def active?(at = Time.current)
    revoked_at.nil? && expires_at > at && context_active?
  end

  def revoke!(reason:, by: nil)
    raise ArgumentError, "reason is required" if reason.blank?

    transaction do
      changed = self.class.where(id: id, revoked_at: nil).update_all(
        revoked_at: Time.current, revocation_reason: reason, updated_at: Time.current
      )
      if changed == 1
        reload
        Agent::AuditEvent.record!(
          subject: self,
          event_type: "operational_authorization.revoked",
          actor: by,
          outcome: "revoked",
          metadata: { "reason" => reason }
        )
        agent_session.cancel_pending_mutations!(reason: reason)
        agent_session.rotate_runtime_authorization!(reason)
      end
    end
    self
  end

  private
    def exact_context
      return unless agent_session && conversation
      errors.add(:base, "must use the exact ACP context") unless
        agent_session.conversation_id == conversation_id &&
        agent_session.household_id == household_id &&
        agent_session.person_id == person_id &&
        browser_session_id.present? && agent_session.browser_session_id == browser_session_id &&
        authorized_by&.person&.household_id == household_id
    end

    def expires_in_future
      errors.add(:expires_at, "must be in the future") unless expires_at&.future?
    end

    def capability_groups_are_exact
      errors.add(:capability_groups, "must contain only health_write") unless capability_groups == CAPABILITY_GROUPS
    end

    def context_active?
      conversation.status == "active" &&
        agent_session.status.in?(%w[ starting connected ]) &&
        agent_session.browser_session_id == browser_session_id &&
        browser_session&.persisted?
    end
end
