class WorkoutBlock < ApplicationRecord
  BLOCK_KINDS = %w[warm_up strength zone2 hiit_interval mobility cooldown_recovery other].freeze
  DOSE_CLASSES = %w[none strength zone2 vigorous].freeze

  belongs_to :workout_template
  has_many :exercise_prescriptions, -> { order(:position) }, dependent: :destroy

  accepts_nested_attributes_for :exercise_prescriptions, allow_destroy: true, reject_if: :all_blank
  before_save :park_changed_prescription_positions

  enum :block_kind, BLOCK_KINDS.index_with(&:itself), prefix: true, validate: true
  enum :dose_class, DOSE_CLASSES.index_with(&:itself), prefix: true, validate: true

  validates :title, presence: true
  validates :position, numericality: { only_integer: true, greater_than: 0 }
  validates :planned_duration_minutes,
    numericality: { only_integer: true, greater_than: 0 },
    allow_nil: true

  def add_prescription
    exercise_prescriptions.build(
      position: active_prescriptions.size + 1,
      entry_kind: "set",
      sets_count: 1
    )
    normalize_positions
  end

  def remove_prescription(index)
    exercise_prescriptions.load_target
    record = exercise_prescriptions.target.fetch(Integer(index))
    record.persisted? ? record.mark_for_destruction : exercise_prescriptions.delete(record)
    normalize_positions
  rescue ArgumentError, IndexError
    raise ArgumentError, "Invalid exercise prescription row."
  end

  def move_prescription(coordinate)
    index, direction = coordinate.to_s.split(":")
    index = Integer(index)
    target = direction == "up" ? index - 1 : index + 1
    records = active_prescriptions
    raise ArgumentError unless %w[up down].include?(direction)
    raise ArgumentError if index.negative? || target.negative? || index >= records.size || target >= records.size

    records[index], records[target] = records[target], records[index]
    exercise_prescriptions.target.replace(records + exercise_prescriptions.target.select(&:marked_for_destruction?))
    normalize_positions
  rescue ArgumentError
    raise ArgumentError, "Invalid exercise prescription row."
  end

  def normalize_positions
    active_prescriptions.each.with_index(1) { |prescription, position| prescription.position = position }
    self
  end

  def ensure_form_rows
    add_prescription if active_prescriptions.empty?
    self
  end

  private
    def active_prescriptions
      exercise_prescriptions.load_target
      exercise_prescriptions.target.reject(&:marked_for_destruction?)
    end

    def park_changed_prescription_positions
      active_prescriptions.select { |prescription| prescription.persisted? && prescription.will_save_change_to_position? }.each do |prescription|
        desired_position = prescription.position
        prescription.update_column(:position, prescription.id + 1_000_000)
        prescription.position = desired_position
      end
    end
end
