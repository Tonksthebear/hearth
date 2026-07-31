class Agent::Message < ApplicationRecord
  include Agent::Contextual
  include Agent::Redactable

  ROLES = %w[ user agent system ].freeze

  belongs_to :household
  belongs_to :person
  belongs_to :conversation, class_name: "Agent::Conversation"
  belongs_to :agent_session, class_name: "Agent::Session", optional: true
  belongs_to :redacted_by, class_name: "User", optional: true

  validates :role, inclusion: { in: ROLES }
  validates :body, presence: true, unless: :redacted_at?
  validates :body_digest, presence: true

  private
    def sensitive_body_columns = %i[ body ]
end
