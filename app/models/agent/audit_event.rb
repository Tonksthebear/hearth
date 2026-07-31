class Agent::AuditEvent < ApplicationRecord
  include Agent::Contextual

  ALLOWED_METADATA_KEYS = %w[ capability capability_groups reason source tool_name ].freeze

  belongs_to :household
  belongs_to :person
  belongs_to :conversation, class_name: "Agent::Conversation"
  belongs_to :agent_session, class_name: "Agent::Session", optional: true
  belongs_to :actor, class_name: "User", optional: true

  validates :subject_type, :subject_id, :event_type, presence: true
  validate :metadata_is_body_free

  scope :for_household, ->(household) { where(household: household) }
  scope :for_person, ->(person) { where(person: person) }
  scope :for_conversation, ->(conversation) { where(conversation: conversation) }

  class << self
    def record!(subject:, event_type:, actor: nil, outcome: nil, body_digest: nil, metadata: {})
      create!(
        household: subject.household,
        person: subject.person,
        conversation: subject.conversation,
        agent_session: subject.try(:agent_session),
        actor: actor,
        subject_type: subject.class.name,
        subject_id: subject.id,
        event_type: event_type,
        outcome: outcome,
        body_digest: body_digest,
        metadata: metadata
      )
    end
  end

  private
    def metadata_is_body_free
      unknown = metadata.keys.map(&:to_s) - ALLOWED_METADATA_KEYS
      errors.add(:metadata, "contains unapproved keys: #{unknown.join(', ')}") if unknown.any?
    end
end
