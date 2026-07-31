class Agent::Installation < ApplicationRecord
  STATUSES = %w[ observed available unavailable ].freeze
  AUTHENTICATION_STATUSES = %w[ unknown required authenticated failed ].freeze
  AUTHENTICATION_METHOD_KEYS = %w[ id name description ].freeze

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

    def contains_secret_key?(value)
      case value
      when Hash
        value.any? do |key, nested|
          key.to_s.match?(/(?:token|secret|password|authorization)\z/i) || contains_secret_key?(nested)
        end
      when Array
        value.any? { |nested| contains_secret_key?(nested) }
      else
        false
      end
    end
end
