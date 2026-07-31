class Agent::Profile < ApplicationRecord
  belongs_to :household

  has_many :installations, class_name: "Agent::Installation", dependent: :restrict_with_exception
  has_many :conversations, class_name: "Agent::Conversation", dependent: :restrict_with_exception

  validates :name, :launch_command, presence: true
  validates :name, uniqueness: { scope: :household_id }
  validate :environment_keys_do_not_contain_values

  private
    def environment_keys_do_not_contain_values
      return if environment_keys.is_a?(Array) &&
        environment_keys.all? { |key| key.is_a?(String) && key.match?(/\A[A-Z][A-Z0-9_]*\z/) }

      errors.add(:environment_keys, "must contain environment variable names only")
    end
end
