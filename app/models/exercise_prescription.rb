class ExercisePrescription < ApplicationRecord
  ENTRY_KINDS = %w[set interval].freeze

  belongs_to :workout_block
  belongs_to :exercise

  enum :entry_kind, ENTRY_KINDS.index_with(&:itself), validate: true
  enum :dose_class, WorkoutBlock::DOSE_CLASSES.index_with(&:itself),
    prefix: true,
    validate: { allow_nil: true }

  validates :position, :sets_count,
    numericality: { only_integer: true, greater_than: 0 }
  validates :rep_min, :rep_max, :work_seconds,
    numericality: { only_integer: true, greater_than: 0 },
    allow_nil: true
  validates :rest_seconds,
    numericality: { only_integer: true, greater_than_or_equal_to: 0 },
    allow_nil: true
  validates :target_rpe, inclusion: { in: 0..10 }, allow_nil: true
  validates :target_rir, inclusion: { in: 0..10 }, allow_nil: true
  validate :rep_range_is_ordered
  validate :rep_range_or_timed_work
  validate :exercise_belongs_to_household

  def effective_dose_class
    dose_class.presence || workout_block.dose_class
  end

  private
    def rep_range_is_ordered
      errors.add(:rep_max, "must be at least the minimum reps") if rep_min && rep_max && rep_max < rep_min
    end

    def rep_range_or_timed_work
      has_rep_range = rep_min.present? || rep_max.present?
      errors.add(:base, "Specify a rep range or timed work.") unless has_rep_range || work_seconds.present?
      errors.add(:base, "Intervals require timed work.") if interval? && work_seconds.blank?
    end

    def exercise_belongs_to_household
      return unless exercise && workout_block&.workout_template
      return if exercise.household_id == workout_block.workout_template.household_id

      errors.add(:exercise, "must belong to this household")
    end
end
