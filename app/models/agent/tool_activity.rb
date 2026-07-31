class Agent::ToolActivity < ApplicationRecord
  include Agent::Contextual
  include Agent::Redactable

  STATUSES = %w[ pending running succeeded failed cancelled ].freeze

  belongs_to :household
  belongs_to :person
  belongs_to :conversation, class_name: "Agent::Conversation"
  belongs_to :agent_session, class_name: "Agent::Session"
  belongs_to :redacted_by, class_name: "User", optional: true

  validates :tool_name, :capability, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :input_body, presence: true, unless: :redacted_at?
  validates :input_digest, presence: true
  validates :output_tokens, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validate :authorization_context_is_active, on: :create

  def start!
    transition_from!("pending", to: "running", started_at: Time.current)
  end

  def succeed!(output_body:, output_tokens:)
    self.output_body = output_body
    self.output_tokens = output_tokens
    transition_from!("running", to: "succeeded", completed_at: Time.current)
  end

  def fail!(output_body: nil)
    self.output_body = output_body
    transition_from!("running", to: "failed", completed_at: Time.current)
  end

  def cancel!
    transition_from!(%w[ pending running ], to: "cancelled", completed_at: Time.current)
  end

  private
    def transition_from!(allowed, to:, **timestamps)
      allowed = Array(allowed)
      unless allowed.include?(status)
        errors.add(:status, "cannot transition from #{status} to #{to}")
        raise ActiveRecord::RecordInvalid, self
      end

      update!(status: to, **timestamps)
      self
    end

    def sensitive_body_columns = %i[ input_body output_body ]

    def authorization_context_is_active
      errors.add(:conversation, "must be active") unless conversation&.status == "active"
      unless agent_session&.status.in?(%w[ starting connected ])
        errors.add(:agent_session, "must be starting or connected")
      end
    end
end
