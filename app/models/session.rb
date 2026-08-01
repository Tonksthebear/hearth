class Session < ApplicationRecord
  belongs_to :user
  has_many :agent_grants,
    class_name: "Agent::Grant",
    foreign_key: :browser_session_id,
    dependent: :nullify,
    inverse_of: :browser_session
  has_many :agent_operational_authorizations,
    class_name: "Agent::OperationalAuthorization",
    foreign_key: :browser_session_id,
    dependent: :nullify,
    inverse_of: :browser_session

  before_destroy :revoke_agent_grants, prepend: true

  private
    def revoke_agent_grants
      agent_operational_authorizations.where(revoked_at: nil).find_each do |authorization|
        authorization.revoke!(reason: "browser session ended")
      end
      agent_grants.where(revoked_at: nil).find_each do |grant|
        grant.revoke!(reason: "browser session ended")
      end
    end
end
