class Agent::Session < ApplicationRecord
  include Agent::Contextual

  STATUSES = %w[ starting connected disconnected closed failed ].freeze

  belongs_to :household
  belongs_to :person
  belongs_to :conversation, class_name: "Agent::Conversation"
  belongs_to :installation, class_name: "Agent::Installation"
  belongs_to :browser_session, class_name: "::Session", optional: true

  has_many :messages, class_name: "Agent::Message", dependent: :nullify
  has_many :grants,
    class_name: "Agent::Grant",
    foreign_key: :agent_session_id,
    dependent: :restrict_with_exception,
    inverse_of: :agent_session

  validates :external_session_id, presence: true, uniqueness: { scope: :installation_id }
  validates :status, inclusion: { in: STATUSES }
  validates :authentication_status, inclusion: { in: Agent::Installation::AUTHENTICATION_STATUSES }
  validate :installation_matches_household
  validate :browser_session_matches_household

  def connect!
    transition_from!(%w[ starting disconnected ], to: "connected", connected_at: Time.current, disconnected_at: nil)
  end

  def disconnect!
    transaction do
      transition_from!(%w[ starting connected ], to: "disconnected", disconnected_at: Time.current)
      revoke_grants!("agent disconnected")
    end
    self
  end

  def close!
    transaction do
      transition_from!(%w[ starting connected disconnected ], to: "closed", closed_at: Time.current)
      revoke_grants!("agent session closed")
    end
    self
  end

  def fail!
    transaction do
      transition_from!(%w[ starting connected disconnected ], to: "failed", disconnected_at: Time.current)
      revoke_grants!("agent session failed")
    end
    self
  end

  private
    def transition_from!(allowed, to:, **timestamps)
      unless allowed.include?(status)
        errors.add(:status, "cannot transition from #{status} to #{to}")
        raise ActiveRecord::RecordInvalid, self
      end

      update!(status: to, **timestamps)
    end

    def revoke_grants!(reason)
      grants.where(revoked_at: nil).find_each { |grant| grant.revoke!(reason: reason) }
    end

    def installation_matches_household
      return if installation_id.blank? || household_id.blank?
      return if Agent::Installation.where(id: installation_id, household_id: household_id).exists?

      errors.add(:installation, "must belong to this household")
    end

    def browser_session_matches_household
      return if browser_session_id.blank? || household_id.blank?
      return if ::Session.joins(user: :person).where(
        id: browser_session_id,
        people: { household_id: household_id }
      ).exists?

      errors.add(:browser_session, "must belong to a user in this household")
    end
end
