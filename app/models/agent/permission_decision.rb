class Agent::PermissionDecision < ApplicationRecord
  OUTCOMES = %w[ approved denied ].freeze

  belongs_to :permission_request, class_name: "Agent::PermissionRequest"
  belongs_to :decided_by, class_name: "User"

  validates :outcome, inclusion: { in: OUTCOMES }
  validates :permission_request_id, uniqueness: true
  validate :actor_matches_household

  delegate :household, :person, :conversation, :agent_session, to: :permission_request

  private
    def actor_matches_household
      return if decided_by_id.blank? || permission_request.blank?
      return if User.joins(:person).where(
        id: decided_by_id,
        people: { household_id: permission_request.household_id }
      ).exists?

      errors.add(:decided_by, "must belong to this household")
    end
end
