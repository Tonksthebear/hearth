class TrainingSet < ApplicationRecord
  LOAD_UNITS = %w[lb kg].freeze
  DISTANCE_UNITS = %w[m km mi ft].freeze

  belongs_to :training_session_exercise

  enum :entry_kind, ExercisePrescription::ENTRY_KINDS.index_with(&:itself), validate: true
  enum :dose_class, WorkoutBlock::DOSE_CLASSES.index_with(&:itself), prefix: true, validate: true
  enum :load_unit, LOAD_UNITS.index_with(&:itself), prefix: true, validate: { allow_nil: true }
  enum :distance_unit, DISTANCE_UNITS.index_with(&:itself), prefix: true, validate: { allow_nil: true }

  validates :position, numericality: { only_integer: true, greater_than: 0 }
  validates :reps, :duration_seconds,
    numericality: { only_integer: true, greater_than: 0 },
    allow_nil: true
  validates :load_amount, :distance_amount,
    numericality: { greater_than: 0 },
    allow_nil: true
  validates :rpe, :rir, inclusion: { in: 0..10 }, allow_nil: true
  validate :load_unit_matches_amount
  validate :distance_unit_matches_amount

  def performance_measurement?
    reps.present? || duration_seconds.present? || distance_amount.present?
  end

  private
    def load_unit_matches_amount
      return if load_amount.present? == load_unit.present?
      errors.add(:load_unit, "must be provided with load")
    end

    def distance_unit_matches_amount
      return if distance_amount.present? == distance_unit.present?
      errors.add(:distance_unit, "must be provided with distance")
    end
end
