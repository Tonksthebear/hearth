class Agent::Turn < ApplicationRecord
  include Agent::Contextual

  STATUSES = %w[ pending claimed running succeeded failed cancelled ].freeze
  TERMINAL_STATUSES = %w[ succeeded failed cancelled ].freeze
  LEASE_DURATION = 15.seconds
  ERROR_LIMIT = 500

  belongs_to :household
  belongs_to :person
  belongs_to :conversation, class_name: "Agent::Conversation"
  belongs_to :agent_session, class_name: "Agent::Session", optional: true
  belongs_to :browser_session, class_name: "::Session"
  belongs_to :user_message, class_name: "Agent::Message"

  validates :idempotency_key, presence: true, uniqueness: { scope: :browser_session_id }
  validates :status, inclusion: { in: STATUSES }
  validates :error_message, length: { maximum: ERROR_LIMIT }, allow_nil: true
  validate :user_message_matches_context

  after_commit :broadcast_status

  scope :unfinished, -> { where.not(status: TERMINAL_STATUSES) }

  class << self
    def recover_stale_claims!(now: Time.current)
      where(status: %w[ claimed running ], lease_expires_at: ..now).find_each do |turn|
        turn.with_lock do
          next if turn.lease_expires_at.nil? || turn.lease_expires_at > now || turn.terminal?

          if turn.dispatched_at?
            turn.update!(status: "failed", completed_at: now, error_message: "ACP runtime stopped after dispatch; submit a new turn to retry")
          else
            turn.update!(status: "pending", claimed_by: nil, claimed_at: nil, lease_expires_at: nil, heartbeat_at: nil)
          end
        end
      end
    end

    def claim_next!(owner:, now: Time.current)
      recover_stale_claims!(now: now)
      where(status: "pending").order(:created_at, :id).find_each do |candidate|
        changed = where(id: candidate.id, status: "pending").update_all(
          status: "claimed",
          claimed_by: owner,
          claimed_at: now,
          heartbeat_at: now,
          lease_expires_at: now + LEASE_DURATION,
          updated_at: now
        )
        return candidate.reload if changed == 1
      end
      nil
    end
  end

  def attach!(session)
    raise ArgumentError, "Agent session must match this turn" unless
      session.household_id == household_id && session.person_id == person_id && session.conversation_id == conversation_id
    raise ActiveRecord::RecordInvalid, self if agent_session_id.present? && agent_session_id != session.id

    update_columns(agent_session_id: session.id, updated_at: Time.current)
    reload
  end

  def dispatch!
    with_lock do
      raise ActiveRecord::RecordInvalid, self unless status == "claimed" && dispatched_at.nil?

      update!(status: "running", dispatched_at: Time.current)
    end
    self
  end

  def heartbeat!
    now = Time.current
    update_columns(heartbeat_at: now, lease_expires_at: now + LEASE_DURATION, updated_at: now) unless terminal?
  end

  def request_cancel!
    with_lock do
      update!(cancel_requested_at: Time.current) unless terminal? || cancel_requested_at?
    end
    self
  end

  def cancellation_requested? = cancel_requested_at.present?

  def mark_cancel_sent!
    update!(cancel_sent_at: Time.current) unless cancel_sent_at?
  end

  def succeed!(stop_reason: nil)
    finish!(cancellation_requested? ? "cancelled" : "succeeded", stop_reason: stop_reason)
  end

  def fail!(error)
    finish!("failed", error_message: error.message.to_s.first(ERROR_LIMIT))
  end

  def terminal? = status.in?(TERMINAL_STATUSES)

  private
    def finish!(status, **attributes)
      with_lock do
        return self if terminal?

        update!({ status: status, completed_at: Time.current, lease_expires_at: nil }.merge(attributes))
      end
      self
    end

    def user_message_matches_context
      return unless user_message
      return if user_message.role == "user" && user_message.conversation_id == conversation_id &&
        user_message.household_id == household_id && user_message.person_id == person_id

      errors.add(:user_message, "must be a user message in this conversation")
    end

    def broadcast_status
      broadcast_replace_to conversation,
        target: "agent_turn_status",
        partial: "agent/conversations/turn_status",
        locals: { turn: conversation.turns.order(created_at: :desc).first }
    end
end
