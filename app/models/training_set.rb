class TrainingSet < ApplicationRecord
  LOAD_UNITS = %w[lb kg].freeze
  DISTANCE_UNITS = %w[m km mi ft].freeze
  COUNT_UNITS = %w[laps flights steps].freeze

  belongs_to :training_session_exercise

  enum :dose_class, WorkoutBlock::DOSE_CLASSES.index_with(&:itself), prefix: true, validate: true
  enum :load_unit, LOAD_UNITS.index_with(&:itself), prefix: true, validate: { allow_nil: true }
  enum :distance_unit, DISTANCE_UNITS.index_with(&:itself), prefix: true, validate: { allow_nil: true }
  enum :count_unit, COUNT_UNITS.index_with(&:itself), prefix: true, validate: { allow_nil: true }

  after_save :sync_exercise_completion
  after_destroy :sync_exercise_completion

  validates :position, numericality: { only_integer: true, greater_than: 0 }
  validates :reps, :duration_seconds, :count,
    numericality: { only_integer: true, greater_than: 0 },
    allow_nil: true
  validates :rest_seconds,
    numericality: { only_integer: true, greater_than_or_equal_to: 0 },
    allow_nil: true
  validates :average_heart_rate_bpm, :peak_heart_rate_bpm,
    numericality: { only_integer: true, greater_than: 0 },
    allow_nil: true
  validates :load_amount, :distance_amount,
    numericality: { greater_than: 0 },
    allow_nil: true
  validates :rpe, :rir, inclusion: { in: 0..10 }, allow_nil: true
  validate :load_unit_matches_amount
  validate :distance_unit_matches_amount
  validate :count_unit_matches_count
  validate :heart_rate_is_ordered
  validate :completed_row_has_required_measurement

  def performance_measurement?
    required_measurement_present?
  end

  def performance_summary
    primary = case training_session_exercise.snapshot_performance_kind
    when "reps" then "#{reps} reps"
    when "duration" then "#{duration_seconds} sec"
    when "distance" then "#{distance_amount.to_f.to_fs(:delimited)} #{distance_unit}"
    when "count" then "#{count} #{count_unit}"
    when "interval" then "#{duration_seconds} sec work / #{rest_seconds} sec recovery"
    end
    secondary = [
      ("#{load_amount.to_f.to_fs(:delimited)} #{load_unit}" if load_amount),
      ("#{distance_amount.to_f.to_fs(:delimited)} #{distance_unit}" if distance_amount && training_session_exercise.snapshot_performance_kind != "distance"),
      ("#{count} #{count_unit}" if count && training_session_exercise.snapshot_performance_kind != "count"),
      ("avg HR #{average_heart_rate_bpm} bpm" if average_heart_rate_bpm),
      ("peak HR #{peak_heart_rate_bpm} bpm" if peak_heart_rate_bpm),
      ("RPE #{rpe.to_f.to_fs(:delimited)}" if rpe),
      ("RIR #{rir.to_f.to_fs(:delimited)}" if rir)
    ].compact
    ([ primary ] + secondary).join(" · ")
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

    def count_unit_matches_count
      return if count.present? == count_unit.present?
      errors.add(:count_unit, "must be provided with count")
    end

    def heart_rate_is_ordered
      return unless average_heart_rate_bpm && peak_heart_rate_bpm
      errors.add(:peak_heart_rate_bpm, "must be at least the average heart rate") if peak_heart_rate_bpm < average_heart_rate_bpm
    end

    def completed_row_has_required_measurement
      return unless completed?
      errors.add(:base, "Record the required performance before completing this row.") unless required_measurement_present?
      if training_session_exercise&.snapshot_performance_kind == "interval" && rest_seconds.blank?
        errors.add(:rest_seconds, "is required for an interval")
      end
    end

    def required_measurement_present?
      case training_session_exercise&.snapshot_performance_kind
      when "reps" then reps.present?
      when "duration", "interval" then duration_seconds.present?
      when "distance" then distance_amount.present? && distance_unit.present?
      when "count" then count.present? && count_unit.present?
      else false
      end
    end

    def sync_exercise_completion
      training_session_exercise.training_sets.reset
      training_session_exercise.sync_completed_at!
    end
end
