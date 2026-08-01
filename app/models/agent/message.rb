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

  after_commit :broadcast_transcript, on: %i[ create update ]
  after_destroy_commit :expire_rendered_body_cache

  def rendered_body
    return render_body if redacted_at?

    Rails.cache.fetch(rendered_body_cache_key) { render_body.to_s }.html_safe
  end

  private
    def sensitive_body_columns = %i[ body ]

    def broadcast_transcript
      expire_rendered_body_cache(body_digest_before_last_save || body_digest) if saved_change_to_body? || saved_change_to_redacted_at?
      broadcast_update_to conversation,
        target: "agent_messages",
        partial: "agent/conversations/messages",
        locals: { messages: conversation.messages.includes(:person, conversation: :profile).order(:created_at, :id) }
    end

    def render_body
      Agent::Message::Markdown.new(body.to_s).to_html
    end

    def rendered_body_cache_key(digest = body_digest)
      [ "agent-message-markdown", 1, digest ]
    end

    def expire_rendered_body_cache(digest = body_digest)
      Rails.cache.delete(rendered_body_cache_key(digest))
    end
end
