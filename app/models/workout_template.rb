class WorkoutTemplate < ApplicationRecord
  PROVENANCE_DESCRIPTIONS = {
    "verified" => "Checked against the cited source.",
    "adapted" => "Intentionally changed from the cited source.",
    "observed" => "Recorded from practice without independent source verification.",
    "personal" => "Created for this household without a claim of clinical endorsement."
  }.freeze

  belongs_to :household
  has_many :workout_blocks, -> { order(:position) }, dependent: :destroy
  has_many :training_sessions, dependent: :nullify

  accepts_nested_attributes_for :workout_blocks, allow_destroy: true, reject_if: :all_blank
  before_save :park_changed_block_positions

  enum :provenance_status, {
    verified: "verified",
    adapted: "adapted",
    observed: "observed",
    personal: "personal"
  }, validate: true

  validates :title, presence: true
  validates :source_name, presence: true, unless: :personal?
  validates :source_url,
    format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https]) },
    allow_blank: true

  def add_block
    workout_blocks.build(
      position: active_blocks.size + 1,
      title: "Workout block",
      block_kind: "other",
      dose_class: "none"
    ).add_prescription
    normalize_positions
  end

  def remove_block(index)
    remove_nested_record(workout_blocks, index, "workout block")
    normalize_positions
  end

  def move_block(coordinate)
    index, direction = parse_move(coordinate)
    workout_blocks.load_target
    move(workout_blocks.target, index, direction)
    normalize_positions
  end

  def add_prescription(block_index)
    block_at(block_index).add_prescription
    normalize_positions
  end

  def remove_prescription(coordinate)
    block_index, prescription_index = parse_coordinate(coordinate, 2)
    block_at(block_index).remove_prescription(prescription_index)
    normalize_positions
  end

  def move_prescription(coordinate)
    block_index, prescription_index, direction = coordinate.to_s.split(":")
    raise ArgumentError, "Invalid exercise prescription row." unless %w[up down].include?(direction)

    block_at(block_index).move_prescription("#{prescription_index}:#{direction}")
    normalize_positions
  rescue ArgumentError
    raise ArgumentError, "Invalid exercise prescription row."
  end

  def normalize_positions
    active_blocks.each.with_index(1) do |block, position|
      block.position = position
      block.normalize_positions
    end
    self
  end

  def ensure_form_rows
    add_block if active_blocks.empty?
    active_blocks.each(&:ensure_form_rows)
    self
  end

  def provenance_description
    PROVENANCE_DESCRIPTIONS.fetch(provenance_status)
  end

  private
    def active_blocks
      workout_blocks.load_target
      workout_blocks.target.reject(&:marked_for_destruction?)
    end

    def block_at(index)
      workout_blocks.load_target
      workout_blocks.target.fetch(Integer(index)).tap do |block|
        raise ArgumentError if block.marked_for_destruction?
      end
    rescue ArgumentError, IndexError
      raise ArgumentError, "Invalid workout block row."
    end

    def parse_coordinate(value, count)
      parts = value.to_s.split(":")
      raise ArgumentError unless parts.size == count

      parts.map { |part| Integer(part) }
    rescue ArgumentError
      raise ArgumentError, "Invalid nested workout row."
    end

    def parse_move(value)
      index, direction = value.to_s.split(":")
      raise ArgumentError unless %w[up down].include?(direction)

      [ Integer(index), direction ]
    rescue ArgumentError
      raise ArgumentError, "Invalid workout block row."
    end

    def move(records, index, direction)
      target = direction == "up" ? index - 1 : index + 1
      raise ArgumentError if index.negative? || target.negative? || index >= records.size || target >= records.size
      raise ArgumentError if records[index].marked_for_destruction? || records[target].marked_for_destruction?

      records[index], records[target] = records[target], records[index]
    rescue ArgumentError
      raise ArgumentError, "Invalid workout block row."
    end

    def remove_nested_record(association, index, label)
      association.load_target
      record = association.target.fetch(Integer(index))
      record.persisted? ? record.mark_for_destruction : association.delete(record)
      self
    rescue ArgumentError, IndexError
      raise ArgumentError, "Invalid #{label} row."
    end

    def park_changed_block_positions
      # Park changed rows beyond index_workout_blocks_on_workout_template_id_and_position
      # before autosave applies their final positions, avoiding transient unique collisions.
      active_blocks.select { |block| block.persisted? && block.will_save_change_to_position? }.each do |block|
        desired_position = block.position
        block.update_column(:position, block.id + 1_000_000)
        block.position = desired_position
      end
    end
end
