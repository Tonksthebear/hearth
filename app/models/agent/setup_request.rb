class Agent::SetupRequest < ApplicationRecord
  ACTIONS = %w[ detect enable authenticate reauthenticate disable ].freeze
  STATUSES = %w[ pending running succeeded failed cancelled expired ].freeze
  TERMINAL_STATUSES = %w[ succeeded failed cancelled expired ].freeze
  ORIGINS = %w[ web cli ].freeze
  LEASE_DURATION = 15.seconds
  SAFE_ERROR_MESSAGES = {
    "adapter_unavailable" => "The certified ACP adapter is not available. Install it outside Hearth, then re-check.",
    "authentication_required" => "Explicit authentication approval is required.",
    "authentication_failed" => "Provider authentication did not complete. Approve a fresh authentication request to retry.",
    "timeout" => "The ACP operation timed out. Approve a fresh request to retry.",
    "invalid_request" => "The setup request is no longer valid. Re-check the provider and try again.",
    "runtime_error" => "The sibling ACP runtime could not complete this request."
  }.freeze

  belongs_to :household
  belongs_to :requested_by, class_name: "User", optional: true

  validates :certified_key, inclusion: { in: ->(*) { Agent::Profile::Certified.keys } }
  validates :action, inclusion: { in: ACTIONS }
  validates :origin, inclusion: { in: ORIGINS }
  validates :status, inclusion: { in: STATUSES }
  validates :idempotency_key, presence: true, uniqueness: { scope: :household_id }
  validates :cli_version, :adapter_version, length: { maximum: 200 }, allow_nil: true
  validates :error_category, length: { maximum: 50 }, allow_nil: true
  validates :error_message, length: { maximum: 300 }, allow_nil: true
  validate :web_actor_matches_household
  validate :authentication_method_shape

  after_commit :broadcast_provider

  scope :unfinished, -> { where.not(status: TERMINAL_STATUSES) }

  class << self
    def enqueue!(household:, certified_key:, action:, idempotency_key:, requested_by: nil,
      origin: requested_by ? "web" : "cli", authentication_method_id: nil)
      existing = household.agent_setup_requests.find_by(idempotency_key: idempotency_key)
      return existing if existing

      create!(household: household, requested_by: requested_by, certified_key: certified_key,
        action: action, authentication_method_id: authentication_method_id,
        idempotency_key: idempotency_key, origin: origin)
    rescue ActiveRecord::RecordNotUnique
      household.agent_setup_requests.find_by!(idempotency_key: idempotency_key)
    end

    def recover_stale_claims!(now: Time.current)
      where(status: "running", lease_expires_at: ..now).find_each do |request|
        request.with_lock do
          next if request.terminal? || request.lease_expires_at.nil? || request.lease_expires_at > now

          if request.dispatched_at?
            request.expire!("authentication_failed")
          else
            request.update!(status: "pending", claimed_by: nil, claimed_at: nil,
              heartbeat_at: nil, lease_expires_at: nil)
          end
        end
      end
    end

    def claim_next!(owner:, now: Time.current)
      recover_stale_claims!(now: now)
      where(status: "pending").order(:created_at, :id).each do |candidate|
        changed = where(id: candidate.id, status: "pending").update_all(status: "running",
          claimed_by: owner, claimed_at: now, heartbeat_at: now,
          lease_expires_at: now + LEASE_DURATION, updated_at: now)
        return candidate.reload if changed == 1
      end
      nil
    end
  end

  def terminal? = status.in?(TERMINAL_STATUSES)
  def cancellable? = status.in?(%w[ pending running ]) && dispatched_at.nil?

  def request_cancel!
    with_lock do
      return self unless cancellable?
      update!(status: "cancelled", cancel_requested_at: Time.current, completed_at: Time.current,
        lease_expires_at: nil)
    end
    self
  end

  def dispatch!
    with_lock do
      raise ActiveRecord::RecordInvalid, self unless status == "running" && dispatched_at.nil?
      update!(dispatched_at: Time.current)
    end
  end

  def heartbeat!
    now = Time.current
    update_columns(heartbeat_at: now, lease_expires_at: now + LEASE_DURATION, updated_at: now) unless terminal?
  end

  def succeed!(attributes = {})
    finish!("succeeded", attributes.merge(error_category: nil, error_message: nil))
  end

  def fail!(category)
    finish!("failed", error_category: category, error_message: SAFE_ERROR_MESSAGES.fetch(category, SAFE_ERROR_MESSAGES["runtime_error"]))
  end

  def expire!(category = "runtime_error")
    finish!("expired", error_category: category, error_message: SAFE_ERROR_MESSAGES.fetch(category, SAFE_ERROR_MESSAGES["runtime_error"]))
  end

  def latest_for_provider?
    self == household.agent_setup_requests.where(certified_key: certified_key).order(created_at: :desc, id: :desc).first
  end

  private
    def finish!(new_status, attributes)
      update!({ status: new_status, completed_at: Time.current, lease_expires_at: nil }.merge(attributes)) unless terminal?
      self
    end

    def web_actor_matches_household
      return unless origin == "web"
      return if requested_by&.person&.household_id == household_id

      errors.add(:requested_by, "must belong to this household")
    end

    def authentication_method_shape
      required = action.in?(%w[ authenticate reauthenticate ])
      if required && authentication_method_id.blank?
        errors.add(:authentication_method_id, "must be explicitly selected")
      elsif authentication_method_id.present? && !authentication_method_id.match?(/\A[a-zA-Z0-9_.:-]{1,100}\z/)
        errors.add(:authentication_method_id, "is invalid")
      end
    end

    def broadcast_provider
      return unless latest_for_provider?

      broadcast_replace_to household,
        target: "agent_provider_#{certified_key}",
        partial: "agent/profiles/provider",
        locals: { provider: Agent::Profile::Certified.fetch(certified_key).state_for(household) }
    end
end
