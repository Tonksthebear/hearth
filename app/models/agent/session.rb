class Agent::Session < ApplicationRecord
  include Agent::Contextual
  include Agent::SecretFreeSnapshot

  STATUSES = %w[ starting connected disconnected closed failed ].freeze
  MCP_AUTHORIZATION_STATUSES = %w[ not_configured authorized reauthorization_required ].freeze
  RECOVERY_ERROR_LIMIT = 500

  belongs_to :household
  belongs_to :person
  belongs_to :conversation, class_name: "Agent::Conversation"
  belongs_to :installation, class_name: "Agent::Installation"
  belongs_to :browser_session, class_name: "::Session", optional: true

  has_many :messages, class_name: "Agent::Message", dependent: :nullify
  has_many :grants,
    class_name: "Agent::Grant",
    foreign_key: :agent_session_id,
    dependent: :restrict_with_exception,
    inverse_of: :agent_session
  has_many :operational_authorizations,
    class_name: "Agent::OperationalAuthorization",
    foreign_key: :agent_session_id,
    dependent: :restrict_with_exception,
    inverse_of: :agent_session
  has_many :mutation_proposals,
    class_name: "Agent::MutationProposal",
    foreign_key: :agent_session_id,
    dependent: :restrict_with_exception,
    inverse_of: :agent_session
  has_many :permission_requests,
    class_name: "Agent::PermissionRequest",
    foreign_key: :agent_session_id,
    dependent: :restrict_with_exception,
    inverse_of: :agent_session
  has_many :turns,
    class_name: "Agent::Turn",
    foreign_key: :agent_session_id,
    dependent: :nullify,
    inverse_of: :agent_session
  has_many :citations,
    class_name: "Agent::Citation",
    foreign_key: :agent_session_id,
    dependent: :restrict_with_exception,
    inverse_of: :agent_session

  validates :external_session_id,
    presence: true,
    unless: -> { status.in?(%w[ starting failed ]) }
  validates :external_session_id,
    uniqueness: { scope: :installation_id },
    allow_nil: true
  validates :status, inclusion: { in: STATUSES }
  validates :authentication_status, inclusion: { in: Agent::Installation::AUTHENTICATION_STATUSES }
  validates :mcp_authorization_status, inclusion: { in: MCP_AUTHORIZATION_STATUSES }
  validates :recovery_attempts, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :recovery_error, length: { maximum: RECOVERY_ERROR_LIMIT }, allow_nil: true
  validate :installation_matches_household
  validate :browser_session_matches_household
  validate :advertised_capabilities_are_secret_free

  scope :recoverable, -> {
    where(status: %w[ starting connected disconnected ])
      .where.not(external_session_id: nil)
      .where("recovery_next_at IS NULL OR recovery_next_at <= ?", Time.current)
  }

  def bind_external_session!(external_session_id)
    raise ArgumentError, "ACP session id is required" if external_session_id.blank?
    if self.external_session_id.present?
      errors.add(:external_session_id, "is already bound")
      raise ActiveRecord::RecordInvalid, self
    end

    update!(external_session_id: external_session_id)
    self
  end

  def issue_runtime_grant!(capability_groups: nil)
    Agent::Grant.issue_runtime!(agent_session: self, capability_groups: capability_groups)
  end

  def active_operational_authorization(at: Time.current)
    operational_authorizations.active_at(at).order(revision: :desc).detect { |authorization| authorization.active?(at) }
  end

  def rotate_runtime_authorization!(reason)
    grants.where(revoked_at: nil).find_each { |grant| grant.revoke!(reason: reason) }
    require_mcp_reauthorization!
    self
  end

  def cancel_pending_mutations!(reason:)
    mutation_proposals.pending.find_each { |proposal| proposal.cancel!(reason: reason) }
  end

  def expire_pending_mutations!
    mutation_proposals.pending.where(deadline_at: ..Time.current).find_each(&:expire_if_needed!)
  end

  def begin_recovery!
    update!(status: "starting") if status == "disconnected"
    self
  end

  def detach_for_authorization_rotation!
    transaction do
      update!(
        status: "disconnected",
        disconnected_at: Time.current,
        mcp_authorization_status: "reauthorization_required"
      )
      revoke_grants!("runtime authorization rotated")
    end
    self
  end

  def fail_initialization!(error)
    transaction do
      transition_from!(
        %w[ starting ],
        to: "failed",
        disconnected_at: Time.current,
        recovery_error: sanitized_recovery_error(error),
        mcp_authorization_status: "reauthorization_required"
      )
      revoke_grants!("agent session initialization failed")
      Agent::AuditEvent.record!(
        subject: self,
        event_type: "session.initialization_failed",
        outcome: "failed",
        metadata: { "reason" => recovery_error }
      )
    end
    self
  end

  def connect!(recovered: false)
    transition_from!(
      %w[ starting disconnected ],
      to: "connected",
      connected_at: Time.current,
      disconnected_at: nil,
      recovery_attempts: 0,
      recovery_next_at: nil,
      recovery_error: nil,
      mcp_authorization_status: recovered ? "reauthorization_required" : mcp_authorization_status
    )
  end

  def disconnect!(reason: "agent disconnected", retry_at: nil, recovery_error: nil)
    transaction do
      transition_from!(
        %w[ starting connected ],
        to: "disconnected",
        disconnected_at: Time.current,
        recovery_next_at: retry_at,
        recovery_error: sanitized_recovery_error(recovery_error),
        mcp_authorization_status: "reauthorization_required"
      )
      revoke_grants!(reason)
      revoke_operational_authorizations!(reason)
      cancel_pending_mutations!(reason: reason)
    end
    self
  end

  def record_recovery_failure!(error:, retry_at:)
    transaction do
      update!(
        status: "disconnected",
        recovery_attempts: recovery_attempts + 1,
        recovery_next_at: retry_at,
        recovery_error: sanitized_recovery_error(error),
        disconnected_at: disconnected_at || Time.current,
        mcp_authorization_status: "reauthorization_required"
      )
      revoke_grants!("agent recovery interrupted")
    end
    self
  end

  def prepare_for_transport_recovery!
    transaction do
      update!(mcp_authorization_status: "reauthorization_required")
      revoke_grants!("ACP transport restarted")
    end
    self
  end

  def fail_recovery!(error)
    transaction do
      transition_from!(
        %w[ starting connected disconnected ],
        to: "failed",
        disconnected_at: Time.current,
        recovery_next_at: nil,
        recovery_error: sanitized_recovery_error(error),
        mcp_authorization_status: "reauthorization_required"
      )
      revoke_grants!("agent session failed")
      Agent::AuditEvent.record!(
        subject: self,
        event_type: "session.recovery_failed",
        outcome: "failed",
        metadata: { "reason" => recovery_error }
      )
    end
    self
  end

  def close!
    transaction do
      transition_from!(%w[ starting connected disconnected ], to: "closed", closed_at: Time.current)
      revoke_grants!("agent session closed")
      revoke_operational_authorizations!("agent session closed")
      cancel_pending_mutations!(reason: "agent session closed")
    end
    self
  end

  def fail!
    transaction do
      transition_from!(
        %w[ starting connected disconnected ],
        to: "failed",
        disconnected_at: Time.current,
        mcp_authorization_status: "reauthorization_required"
      )
      revoke_grants!("agent session failed")
    end
    self
  end

  def authorize_mcp!
    update!(mcp_authorization_status: "authorized")
  end

  def require_mcp_reauthorization!
    return self if mcp_authorization_status == "reauthorization_required"

    update!(mcp_authorization_status: "reauthorization_required")
  end

  def require_mcp_authorized!
    return self if mcp_authorization_status == "authorized"

    raise Agent::Grant::AuthorizationRequired, "MCP authorization requires an authenticated browser grant"
  end

  private
    def transition_from!(allowed, to:, **timestamps)
      unless allowed.include?(status)
        errors.add(:status, "cannot transition from #{status} to #{to}")
        raise ActiveRecord::RecordInvalid, self
      end

      update!(status: to, **timestamps)
    end

    def revoke_grants!(reason)
      grants.where(revoked_at: nil).find_each { |grant| grant.revoke!(reason: reason) }
    end

    def revoke_operational_authorizations!(reason)
      operational_authorizations.where(revoked_at: nil).find_each do |authorization|
        authorization.revoke!(reason: reason)
      end
    end

    def sanitized_recovery_error(error)
      return if error.blank?

      error.to_s.encode("UTF-8", invalid: :replace, undef: :replace, replace: "?")
        .gsub(/[\r\n\t]+/, " ")
        .gsub(%r{/(?:[^/\s]+/)+[^/\s]+}, "[path]")
        .squeeze(" ")
        .first(RECOVERY_ERROR_LIMIT)
    end

    def installation_matches_household
      return if installation_id.blank? || household_id.blank?
      return if Agent::Installation.where(id: installation_id, household_id: household_id).exists?

      errors.add(:installation, "must belong to this household")
    end

    def browser_session_matches_household
      return if browser_session_id.blank? || household_id.blank?
      return if ::Session.joins(user: :person).where(
        id: browser_session_id,
        people: { household_id: household_id }
      ).exists?

      errors.add(:browser_session, "must belong to a user in this household")
    end

    def advertised_capabilities_are_secret_free
      return unless contains_secret_key?(advertised_capabilities)

      errors.add(:advertised_capabilities, "cannot contain secrets")
    end
end
