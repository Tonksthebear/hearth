class Agent::Conversation < ApplicationRecord
  include Agent::Contextual

  STATUSES = %w[ active closed ].freeze

  belongs_to :household
  belongs_to :person
  belongs_to :profile, class_name: "Agent::Profile"

  has_many :sessions, class_name: "Agent::Session", dependent: :restrict_with_exception
  has_many :messages, class_name: "Agent::Message", dependent: :restrict_with_exception
  has_many :audit_events, class_name: "Agent::AuditEvent", dependent: :restrict_with_exception

  validates :title, presence: true
  validates :status, inclusion: { in: STATUSES }
  validate :profile_matches_household

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
