class Exercise < ApplicationRecord
  MODALITIES = %w[strength cardio mobility balance recovery mixed other].freeze
  MOVEMENT_PATTERNS = %w[
    squat hinge lunge horizontal_push vertical_push horizontal_pull vertical_pull
    carry core locomotion_cardio mobility balance other
  ].freeze

  belongs_to :household
  has_many :exercise_prescriptions, dependent: :restrict_with_exception
  has_many :training_session_exercises, dependent: :nullify
  has_many :exercise_visuals, -> { order(:position) }, inverse_of: :exercise, dependent: :destroy
  has_many :exercise_muscle_targets, dependent: :destroy, inverse_of: :exercise
  has_many :muscles, through: :exercise_muscle_targets

  accepts_nested_attributes_for :exercise_visuals, allow_destroy: true
  before_validation :normalize_source_identity
  before_save :park_changed_nested_positions

  enum :modality, MODALITIES.index_with(&:itself), prefix: true, validate: true
  enum :movement_pattern, MOVEMENT_PATTERNS.index_with(&:itself), prefix: true, validate: true

  validates :name, presence: true, uniqueness: { scope: :household_id }
  validates :source_key, uniqueness: { scope: :household_id }, allow_nil: true
  validate :source_snapshot_is_object
  validate :source_removed_at_requires_source_key

  scope :from_source, -> { where.not(source_key: nil) }

  class << self
    def merge_source_record!(household:, record:)
      SourceMerge.new(household:, record:).merge_record!
    end

    def mark_sources_removed!(household:, present_source_keys:)
      SourceMerge.mark_removed!(household:, present_source_keys:)
    end
  end

  def add_visual
    exercise_visuals.build(
      position: active_visuals.size + 1,
      kind: "image",
      provenance_status: "personal"
    ).add_item
    normalize_positions
  end

  def remove_visual(index)
    remove_nested_record(exercise_visuals, index, "exercise visual")
    normalize_positions
  end

  def add_visual_item(visual_index)
    visual_at(visual_index).add_item
    normalize_positions
  end

  def remove_visual_item(coordinate)
    visual_index, item_index = parse_coordinate(coordinate)
    visual_at(visual_index).remove_item(item_index)
    normalize_positions
  end

  def normalize_positions
    sorted_visuals.each.with_index(1) do |visual, position|
      visual.position = position
      visual.normalize_positions
    end
    self
  end

  def preserve_visuals_for_form
    active_visuals.each(&:preserve_items_for_form)
    self
  end

  def ordered_muscle_targets
    exercise_muscle_targets.in_display_order
  end

  def source_linked?
    source_key.present?
  end

  def source_removed?
    source_removed_at.present?
  end

  def merges_automatically?
    source_linked? && !source_removed?
  end

  private
    def normalize_source_identity
      self.source_key = source_key.presence
      self.source_version = source_version.presence
      self.source_snapshot = {} if source_snapshot.nil?
    end

    def source_snapshot_is_object
      errors.add(:source_snapshot, "must be an object") unless source_snapshot.is_a?(Hash)
    end

    def source_removed_at_requires_source_key
      return if source_removed_at.blank? || source_key.present?

      errors.add(:source_removed_at, "requires a source key")
    end

    def active_visuals
      exercise_visuals.load_target
      exercise_visuals.target.reject(&:marked_for_destruction?)
    end

    def sorted_visuals
      active_visuals.sort_by { |visual| [ visual.position || Float::INFINITY, visual.object_id ] }
    end

    def visual_at(index)
      exercise_visuals.load_target
      exercise_visuals.target.fetch(Integer(index)).tap do |visual|
        raise ArgumentError if visual.marked_for_destruction?
      end
    rescue ArgumentError, IndexError
      raise ArgumentError, "Invalid exercise visual row."
    end

    def parse_coordinate(value)
      parts = value.to_s.split(":")
      raise ArgumentError unless parts.size == 2

      parts.map { |part| Integer(part) }
    rescue ArgumentError
      raise ArgumentError, "Invalid visual item row."
    end

    def remove_nested_record(association, index, label)
      association.load_target
      record = association.target.fetch(Integer(index))
      record.persisted? ? record.mark_for_destruction : association.delete(record)
      self
    rescue ArgumentError, IndexError
      raise ArgumentError, "Invalid #{label} row."
    end

    def park_changed_nested_positions
      # Park changed rows beyond their per-exercise unique position indexes before
      # autosave applies final 1-based positions, avoiding transient collisions.
      active_visuals.select { |record| record.persisted? && record.will_save_change_to_position? }.each do |record|
        desired_position = record.position
        record.update_column(:position, record.id + 1_000_000)
        record.position = desired_position
      end
    end
end
