class Session < ApplicationRecord
  belongs_to :user
  has_many :agent_grants,
    class_name: "Agent::Grant",
    foreign_key: :browser_session_id,
    dependent: :nullify,
    inverse_of: :browser_session

  before_destroy :revoke_agent_grants, prepend: true

  private
    def revoke_agent_grants
      agent_grants.where(revoked_at: nil).update_all(
        revoked_at: Time.current,
        revocation_reason: "browser session ended",
        updated_at: Time.current
      )
    end
end
