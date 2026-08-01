class Agent::Message < ApplicationRecord
  include Agent::Contextual
  include Agent::Redactable

  ROLES = %w[ user agent system ].freeze
  SOURCE_KINDS = %w[ hearth_fact vault_knowledge external_search agent_suggestion ].freeze

  belongs_to :household
  belongs_to :person
  belongs_to :conversation, class_name: "Agent::Conversation"
  belongs_to :agent_session, class_name: "Agent::Session", optional: true
  belongs_to :redacted_by, class_name: "User", optional: true
  has_many :citations, class_name: "Agent::Citation", dependent: :nullify

  validates :role, inclusion: { in: ROLES }
  validates :body, presence: true, unless: :redacted_at?
  validates :body_digest, presence: true
  validates :source_kind, inclusion: { in: SOURCE_KINDS }

  after_create_commit :broadcast_created
  after_update_commit :broadcast_updated

  def rendered_body
    Agent::Message::Markdown.new(body.to_s).to_html
  end

  private
    def sensitive_body_columns = %i[ body ]

    def broadcast_created
      broadcast_update_to conversation,
        target: "agent_messages",
        partial: "agent/conversations/messages",
        locals: { messages: conversation.messages.order(:created_at, :id) }
    end

    def broadcast_updated
      broadcast_created
    end
end
