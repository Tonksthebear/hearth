class ExerciseVisual < ApplicationRecord
  KINDS = %w[image frame_sequence video].freeze
  DEFAULT_FRAME_INTERVAL_MS = 700
  FRAME_INTERVAL_RANGE = 100..5000

  belongs_to :exercise, inverse_of: :exercise_visuals
  has_many :exercise_visual_items, -> { order(:position) }, inverse_of: :exercise_visual, dependent: :destroy

  accepts_nested_attributes_for :exercise_visual_items, allow_destroy: true
  before_validation :assign_default_frame_interval
  before_save :park_changed_nested_positions

  enum :kind, KINDS.index_with(&:itself), validate: true
  enum :provenance_status, {
    personal: "personal",
    verified: "verified",
    adapted: "adapted",
    observed: "observed"
  }, validate: true

  validates :position, numericality: { only_integer: true, greater_than: 0 }
  validates :alt_text, presence: true
  validates :source_key, uniqueness: { scope: :exercise_id }, allow_nil: true
  validates :frame_interval_ms,
    numericality: { only_integer: true, in: FRAME_INTERVAL_RANGE },
    if: :frame_sequence?
  validates :frame_interval_ms, absence: true, unless: :frame_sequence?
  validate :item_count_matches_kind

  def add_item
    exercise_visual_items.build(position: active_items.size + 1)
    normalize_positions
  end

  def remove_item(index)
    exercise_visual_items.load_target
    record = exercise_visual_items.target.fetch(Integer(index))
    record.persisted? ? record.mark_for_destruction : exercise_visual_items.delete(record)
    normalize_positions
  rescue ArgumentError, IndexError
    raise ArgumentError, "Invalid visual item row."
  end

  def normalize_positions
    sorted_items.each.with_index(1) { |item, position| item.position = position }
    self
  end

  def preserve_items_for_form
    active_items.each(&:preserve_file_for_form)
    self
  end

  def animated_items
    exercise_visual_items.select(&:inline_renderable?)
  end

  def download_items
    exercise_visual_items.reject(&:inline_renderable?)
  end

  def active_items
    exercise_visual_items.load_target
    exercise_visual_items.target.reject(&:marked_for_destruction?)
  end

  def sorted_items
    active_items.sort_by { |item| [ item.position || Float::INFINITY, item.object_id ] }
  end

  def thumbnail_item
    sorted_items.first
  end

  def unmodified_source_art?
    return false unless source_key.present? && source_key.start_with?("workout_guide:")

    snapshot = exercise&.source_snapshot
    return false unless snapshot.is_a?(Hash)

    base = snapshot.dig("visuals", source_key)
    return false if base.blank?

    current_pairs = sorted_items.map { |item|
      [ item.source_identifier, item.file.attached? ? item.file.blob.checksum : nil ]
    }
    base_pairs = Array(base["items"]).map { |item|
      [ item["source_identifier"], item["content_digest"] ]
    }
    current_pairs == base_pairs
  end

  private
    def assign_default_frame_interval
      if frame_sequence?
        self.frame_interval_ms = DEFAULT_FRAME_INTERVAL_MS if frame_interval_ms.blank?
      elsif frame_interval_ms.blank?
        self.frame_interval_ms = nil
      end
    end

    def item_count_matches_kind
      count = active_items.size
      if image? || video?
        errors.add(:exercise_visual_items, "must have exactly one item") unless count == 1
      elsif frame_sequence?
        errors.add(:exercise_visual_items, "must have at least two items") if count < 2
      end
    end

    def park_changed_nested_positions
      # Park changed rows beyond their per-visual unique position indexes before
      # autosave applies final 1-based positions, avoiding transient collisions.
      active_items.select { |record| record.persisted? && record.will_save_change_to_position? }.each do |record|
        desired_position = record.position
        record.update_column(:position, record.id + 1_000_000)
        record.position = desired_position
      end
    end
end
