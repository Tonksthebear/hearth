class Agent::Installation < ApplicationRecord
  include Agent::SecretFreeSnapshot

  STATUSES = %w[ observed available unavailable ].freeze
  AUTHENTICATION_STATUSES = %w[ unknown not_required required authenticated failed ].freeze
  AUTHENTICATION_ORIGINS = %w[ operator_command web_setting ].freeze
  AUTHENTICATION_METHOD_KEYS = %w[ id name ].freeze

  belongs_to :household
  belongs_to :profile, class_name: "Agent::Profile"

  has_many :sessions, class_name: "Agent::Session", dependent: :restrict_with_exception

  validates :external_id, :executable_path, presence: true
  validates :external_id, uniqueness: { scope: :household_id }
  validates :protocol_version, numericality: { only_integer: true, greater_than: 0 }
  validates :status, inclusion: { in: STATUSES }
  validates :authentication_status, inclusion: { in: AUTHENTICATION_STATUSES }
  validate :profile_matches_household
  validate :authentication_snapshot_is_secret_free
  validate :authentication_methods_are_metadata_only
  validate :authentication_approval_is_complete

  def observe!(protocol_version:, capabilities:, authentication_methods:, authentication_status:, agent_version:)
    update!(
      protocol_version: protocol_version,
      status: "available",
      advertised_capabilities: capabilities,
      authentication_methods: authentication_methods,
      authentication_status: authentication_status,
      agent_version: agent_version.presence || self.agent_version,
      last_seen_at: Time.current
    )
  end

  def approved_authentication_method
    return unless authentication_method_id.present? && authentication_approved_at.present?
    return unless authentication_methods.any? { |method| method["id"] == authentication_method_id }

    authentication_method_id
  end

  def approve_authentication!(method_id:, origin: "operator_command", at: Time.current)
    unless authentication_methods.any? { |method| method["id"] == method_id }
      errors.add(:authentication_method_id, "must be advertised by the ACP agent")
      raise ActiveRecord::RecordInvalid, self
    end

    update!(
      authentication_status: "authenticated",
      authentication_method_id: method_id,
      authentication_approved_at: at,
      authentication_origin: origin
    )
  end

  def require_authentication!
    update!(
      authentication_status: authentication_methods.empty? ? "not_required" : "required",
      authentication_method_id: nil,
      authentication_approved_at: nil,
      authentication_origin: nil
    )
  end

  def authentication_failed!
    update!(authentication_status: "failed")
  end

  private
    def profile_matches_household
      return if profile_id.blank? || household_id.blank?
      return if Agent::Profile.where(id: profile_id, household_id: household_id).exists?

      errors.add(:profile, "must belong to this household")
    end

    def authentication_snapshot_is_secret_free
      return unless contains_secret_key?(authentication_methods) || contains_secret_key?(advertised_capabilities)

      errors.add(:base, "Authentication and capability snapshots cannot contain secrets")
    end

    def authentication_methods_are_metadata_only
      valid = authentication_methods.is_a?(Array) && authentication_methods.all? do |method|
        method.is_a?(Hash) &&
          (method.keys.map(&:to_s) - AUTHENTICATION_METHOD_KEYS).empty? &&
          method.values.all? { |value| value.nil? || value.is_a?(String) }
      end
      errors.add(:authentication_methods, "must contain ACP method metadata only") unless valid
    end


    def authentication_approval_is_complete
      values = [ authentication_method_id, authentication_approved_at, authentication_origin ]
      return if values.all?(&:blank?)

      errors.add(:base, "Authentication approval metadata must be complete") unless values.none?(&:blank?)
      if authentication_origin.present? && !AUTHENTICATION_ORIGINS.include?(authentication_origin)
        errors.add(:authentication_origin, "is not included in the list")
      end
    end
end
