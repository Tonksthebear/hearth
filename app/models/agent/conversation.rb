require "digest"

class Agent::Conversation < ApplicationRecord
  include Agent::Contextual

  STATUSES = %w[ active closed ].freeze

  belongs_to :household
  belongs_to :person
  belongs_to :profile, class_name: "Agent::Profile"

  has_many :sessions, class_name: "Agent::Session", dependent: :restrict_with_exception
  has_many :messages, class_name: "Agent::Message", dependent: :restrict_with_exception
  has_many :turns, class_name: "Agent::Turn", dependent: :restrict_with_exception
  has_many :citations, class_name: "Agent::Citation", dependent: :restrict_with_exception
  has_many :tool_activities, class_name: "Agent::ToolActivity", dependent: :restrict_with_exception
  has_one :plan, class_name: "Agent::Plan", dependent: :destroy
  has_many :audit_events, class_name: "Agent::AuditEvent", dependent: :restrict_with_exception
  has_many :operational_authorizations, class_name: "Agent::OperationalAuthorization", dependent: :restrict_with_exception
  has_many :mutation_proposals, class_name: "Agent::MutationProposal", dependent: :restrict_with_exception

  validates :title, presence: true
  validates :status, inclusion: { in: STATUSES }
  validate :profile_matches_household

  def enqueue_turn!(body:, browser_session:, idempotency_key:)
    existing = turns.find_by(browser_session: browser_session, idempotency_key: idempotency_key)
    return existing if existing

    transaction do
      message = messages.create!(
        household: household,
        person: person,
        role: "user",
        body: body,
        body_digest: Digest::SHA256.hexdigest(body),
        source_kind: "hearth_fact"
      )
      turns.create!(
        household: household,
        person: person,
        browser_session: browser_session,
        user_message: message,
        idempotency_key: idempotency_key
      )
    end
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
    turns.find_by(browser_session: browser_session, idempotency_key: idempotency_key) || raise
  end

  def accepts_turns?
    status == "active" && profile.enabled?
  end

  def close!
    return self if status == "closed"
    raise ActiveRecord::RecordInvalid, self unless status == "active"

    transaction do
      sessions.where(status: %w[ starting connected disconnected ]).find_each(&:close!)
      update!(status: "closed", closed_at: Time.current)
    end
    self
  end

  private
    def profile_matches_household
      return if household_id.blank?
      if profile
        return if profile.household == household

        errors.add(:profile, "must belong to this household")
        return
      end
      return if profile_id.blank?
      return if Agent::Profile.where(id: profile_id, household_id: household_id).exists?

      errors.add(:profile, "must belong to this household")
    end
end
