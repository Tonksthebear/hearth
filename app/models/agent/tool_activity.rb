class Agent::ToolActivity < ApplicationRecord
  require "digest"
  include Agent::Contextual
  include Agent::Redactable

  STATUSES = %w[ pending running succeeded failed cancelled ].freeze
  SOURCES = %w[ mcp acp ].freeze

  belongs_to :household
  belongs_to :person
  belongs_to :conversation, class_name: "Agent::Conversation"
  belongs_to :agent_session, class_name: "Agent::Session"
  belongs_to :redacted_by, class_name: "User", optional: true

  validates :tool_name, presence: true, if: -> { source == "mcp" }
  validates :display_title, :kind, presence: true, if: -> { source == "acp" }
  validates :source, inclusion: { in: SOURCES }
  validates :capability, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :input_body, presence: true, unless: :redacted_at?
  validates :input_digest, presence: true
  validates :output_tokens, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validate :authorization_context_is_active, on: :create

  after_create_commit :broadcast_created
  after_update_commit :broadcast_updated

  class << self
    def record_mcp_call!(grant:, tool_name:, arguments:, result:, failed: false, capability:, provenance: {})
      input_json = JSON.generate(arguments || {})
      output_json = JSON.generate(result)
      now = Time.current
      create!(
        household: grant.household,
        person: grant.person,
        conversation: grant.conversation,
        agent_session: grant.agent_session,
        tool_name: tool_name,
        capability: capability,
        status: failed ? "failed" : "succeeded",
        input_body: nil,
        input_digest: Digest::SHA256.hexdigest(input_json),
        output_body: nil,
        output_digest: Digest::SHA256.hexdigest(output_json),
        output_tokens: (output_json.bytesize / 4.0).ceil,
        provenance: bounded_provenance(provenance),
        redacted_at: now,
        redaction_reason: capability.start_with?("knowledge.") ?
          "MCP knowledge payloads are digest-only" : "MCP health data is digest-only",
        started_at: now,
        completed_at: now
      )
    end

    private
      def bounded_provenance(value)
        candidate = value.to_h.stringify_keys
        candidate = candidate.fetch("provenance", candidate).to_h.stringify_keys
        candidate.slice("contract_version", "source_commit", "submission_id", "state", "truncated")
      end
  end

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

    def broadcast_created
      broadcast_append_to conversation,
        target: "agent_activities",
        partial: "agent/conversations/activity",
        locals: { activity: self }
    end

    def broadcast_updated
      broadcast_replace_to conversation,
        target: self,
        partial: "agent/conversations/activity",
        locals: { activity: self }
    end
end
