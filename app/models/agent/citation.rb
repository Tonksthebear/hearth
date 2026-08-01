require "uri"

class Agent::Citation < ApplicationRecord
  include Agent::Contextual

  belongs_to :household
  belongs_to :person
  belongs_to :conversation, class_name: "Agent::Conversation"
  belongs_to :agent_session, class_name: "Agent::Session"
  belongs_to :message, class_name: "Agent::Message", optional: true

  validates :external_id, :title, presence: true
  validates :external_id, uniqueness: { scope: :agent_session_id }
  validates :source_kind, inclusion: { in: Agent::Message::SOURCE_KINDS }
  validate :safe_url

  after_commit :broadcast_citations

  private
    def safe_url
      return if url.blank?

      uri = URI.parse(url)
      errors.add(:url, "must use HTTP or HTTPS") unless uri.is_a?(URI::HTTP)
    rescue URI::InvalidURIError
      errors.add(:url, "is invalid")
    end

    def broadcast_citations
      broadcast_replace_to conversation,
        target: "agent_citations",
        partial: "agent/conversations/citations",
        locals: { citations: conversation.citations.order(:created_at) }
    end
end
