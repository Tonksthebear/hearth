require "psych"
require "yaml"

class Muscle < ApplicationRecord
  CATALOG_PATH = Rails.root.join("config/muscles.yml")
  MUSCLE_GROUPS = %w[chest shoulders arms back core hips legs].freeze

  class << self
    def load_catalog(text)
      duplicates = duplicate_mapping_keys(Psych.parse(text))
      raise ArgumentError, "Duplicate muscle keys: #{duplicates.join(", ")}" if duplicates.any?

      YAML.safe_load(text, permitted_classes: [], permitted_symbols: [], aliases: false)
        .map { |key, attributes|
          {
            key: key,
            name: attributes.fetch("name"),
            muscle_group: attributes.fetch("muscle_group"),
            aliases: Array(attributes.fetch("aliases")),
            display_position: attributes.fetch("display_position")
          }
        }
        .sort_by { |row| row.fetch(:display_position) }
    end

    def duplicate_mapping_keys(node)
      case node
      when Psych::Nodes::Stream, Psych::Nodes::Document, Psych::Nodes::Sequence
        node.children.flat_map { |child| duplicate_mapping_keys(child) }
      when Psych::Nodes::Mapping
        keys = node.children.each_slice(2).filter_map { |key, _value|
          key.value if key.respond_to?(:value)
        }
        duplicates = keys.tally.select { |_key, count| count > 1 }.keys
        duplicates + node.children.each_slice(2).flat_map { |_key, value| duplicate_mapping_keys(value) }
      else
        []
      end
    end

    def ensure_defaults!
      transaction do
        DEFAULTS.each do |attributes|
          muscle = find_or_initialize_by(key: attributes.fetch(:key))
          muscle.assign_attributes(attributes)
          muscle.save!
        end

        aliases = pluck(:aliases).flatten
        raise ArgumentError, "Duplicate muscle aliases: #{aliases.tally.select { |_name, count| count > 1 }.keys.join(", ")}" if aliases.size != aliases.uniq.size
      end
    end

    def resolve_source_name(source_name)
      displayed.find { |muscle| muscle.aliases.include?(source_name) }
    end
  end

  DEFAULTS = load_catalog(CATALOG_PATH.read).freeze
  KEYS = DEFAULTS.map { |row| row.fetch(:key) }.freeze

  has_many :exercise_muscle_targets, dependent: :restrict_with_exception
  has_many :exercises, through: :exercise_muscle_targets

  validates :key, :name, :muscle_group, presence: true
  validates :key, uniqueness: true, inclusion: { in: KEYS }
  validates :muscle_group, inclusion: { in: MUSCLE_GROUPS }
  validates :display_position, numericality: { only_integer: true, greater_than: 0 }, uniqueness: true
  validate :stable_identity, on: :update
  validate :aliases_are_unique_strings
  validate :aliases_are_unique_across_muscles

  scope :displayed, -> { order(:display_position) }

  private
    def stable_identity
      errors.add(:key, "cannot change") if will_save_change_to_key?
    end

    def aliases_are_unique_strings
      unless aliases.is_a?(Array) && aliases.all? { |value| value.is_a?(String) && value.present? }
        errors.add(:aliases, "must be an array of present strings")
        return
      end

      errors.add(:aliases, "contains duplicates") if aliases.size != aliases.uniq.size
    end

    def aliases_are_unique_across_muscles
      return unless aliases.is_a?(Array)

      aliases.each do |alias_name|
        clash = self.class.where.not(id: id).find { |other| other.aliases.include?(alias_name) }
        errors.add(:aliases, "contains #{alias_name.inspect}, already used") if clash
      end
    end
end
