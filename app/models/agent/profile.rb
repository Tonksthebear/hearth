require "pathname"

class Agent::Profile < ApplicationRecord
  UPDATE_POLICIES = %w[ manual ].freeze

  belongs_to :household

  has_many :installations, class_name: "Agent::Installation", dependent: :restrict_with_exception
  has_many :conversations, class_name: "Agent::Conversation", dependent: :restrict_with_exception

  validates :name, :executable_path, presence: true
  validates :executable_path, format: {
    without: /[[:space:]\0]/,
    message: "must be one explicit executable without shell whitespace"
  }
  validates :name, uniqueness: { scope: :household_id }
  validates :certified_key, uniqueness: { scope: :household_id }, allow_nil: true
  validates :update_policy, inclusion: { in: UPDATE_POLICIES }
  validate :arguments_are_explicit
  validate :environment_keys_do_not_contain_values
  validate :working_directory_is_relative_and_contained

  def argv
    [ executable_path, *arguments ]
  end

  def environment_from(source = ENV)
    source.slice(*environment_keys)
  end

  def working_directory_for(instance_root)
    root = Pathname.new(instance_root).expand_path
    directory = working_directory.present? ? root.join(working_directory).expand_path : root
    unless directory == root || directory.to_s.start_with?("#{root}#{File::SEPARATOR}")
      raise ArgumentError, "Agent working directory must stay inside the Hearth instance root"
    end

    directory.to_s
  end

  def disable_runtime_access!
    transaction do
      update!(enabled: false)
      installations.find_each(&:require_authentication!)
      conversations.includes(:sessions).find_each do |conversation|
        conversation.sessions.where(status: %w[ starting connected disconnected ]).find_each do |session|
          session.close!
        end
      end
    end
    self
  end

  private
    def arguments_are_explicit
      return if arguments.is_a?(Array) && arguments.all? { |argument| argument.is_a?(String) }

      errors.add(:arguments, "must contain argv strings")
    end

    def environment_keys_do_not_contain_values
      return if environment_keys.is_a?(Array) &&
        environment_keys.all? { |key| key.is_a?(String) && key.match?(/\A[A-Z][A-Z0-9_]*\z/) }

      errors.add(:environment_keys, "must contain environment variable names only")
    end

    def working_directory_is_relative_and_contained
      return if working_directory.blank?

      directory = Pathname.new(working_directory)
      normalized = directory.cleanpath.to_s
      return unless directory.absolute? || normalized == ".." || normalized.start_with?("../")

      errors.add(:working_directory, "must stay inside the Hearth instance root")
    end
end
