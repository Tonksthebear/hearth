class ExercisePrescription < ApplicationRecord
  include TargetMeasurements

  PERFORMANCE_KINDS = %w[reps duration distance count interval].freeze
  DISTANCE_UNITS = TrainingSet::DISTANCE_UNITS
  COUNT_UNITS = TrainingSet::COUNT_UNITS
  HEART_RATE_UNITS = %w[bpm percent_max].freeze

  belongs_to :workout_block
  belongs_to :exercise

  enum :performance_kind, PERFORMANCE_KINDS.index_with(&:itself), prefix: true, validate: true
  enum :target_distance_unit, DISTANCE_UNITS.index_with(&:itself), prefix: true, validate: { allow_nil: true }
  enum :target_count_unit, COUNT_UNITS.index_with(&:itself), prefix: true, validate: { allow_nil: true }
  enum :target_heart_rate_unit, HEART_RATE_UNITS.index_with(&:itself), prefix: true, validate: { allow_nil: true }
  enum :dose_class, WorkoutBlock::DOSE_CLASSES.index_with(&:itself),
    prefix: true,
    validate: { allow_nil: true }

  validates :position, :sets_count,
    numericality: { only_integer: true, greater_than: 0 }
  validates :rep_min, :rep_max, :work_seconds, :target_count,
    numericality: { only_integer: true, greater_than: 0 },
    allow_nil: true
  validates :target_distance_amount,
    numericality: { greater_than: 0 },
    allow_nil: true
  validates :rest_seconds,
    numericality: { only_integer: true, greater_than_or_equal_to: 0 },
    allow_nil: true
  validates :target_rpe, inclusion: { in: 0..10 }, allow_nil: true
  validates :target_rir, inclusion: { in: 0..10 }, allow_nil: true
  validates :target_heart_rate_min, :target_heart_rate_max,
    numericality: { only_integer: true, greater_than: 0 },
    allow_nil: true
  validates_target_measurements(
    performance_kind: :performance_kind,
    rep_min: :rep_min,
    rep_max: :rep_max,
    work_seconds: :work_seconds,
    rest_seconds: :rest_seconds,
    distance_amount: :target_distance_amount,
    distance_unit: :target_distance_unit,
    count: :target_count,
    count_unit: :target_count_unit,
    heart_rate_min: :target_heart_rate_min,
    heart_rate_max: :target_heart_rate_max,
    heart_rate_unit: :target_heart_rate_unit
  )
  validate :exercise_belongs_to_household

  def effective_dose_class
    dose_class.presence || workout_block.dose_class
  end

  def target_summary
    primary = case performance_kind
    when "reps"
      range = [ rep_min, rep_max ].compact.join("–")
      "#{range} reps" if range.present?
    when "duration" then "#{work_seconds} sec" if work_seconds
    when "distance"
      "#{target_distance_amount.to_f.to_fs(:delimited)} #{target_distance_unit}" if target_distance_amount && target_distance_unit
    when "count" then "#{target_count} #{target_count_unit}" if target_count && target_count_unit
    when "interval" then "#{work_seconds} sec work / #{rest_seconds} sec recovery" if work_seconds && rest_seconds
    end
    row_name = performance_kind == "interval" ? "round" : "row"
    [ "#{sets_count} #{row_name.pluralize(sets_count)}", primary ].compact.join(" · ")
  end

  def cue_summary
    [
      ("per side" if per_side?),
      tempo_cue.presence,
      load_guidance.presence,
      heart_rate_summary,
      ("RPE #{target_rpe.to_f.to_fs(:delimited)}" if target_rpe),
      ("RIR #{target_rir.to_f.to_fs(:delimited)}" if target_rir),
      ("#{rest_seconds} sec rest" if rest_seconds && !performance_kind_interval?)
    ].compact.join(" · ")
  end

  def heart_rate_summary
    return if target_heart_rate_min.blank? && target_heart_rate_max.blank?
    value = [ target_heart_rate_min, target_heart_rate_max ].compact.join("–")
    "HR #{value} #{target_heart_rate_unit == "percent_max" ? "% max" : "bpm"}"
  end

  private
    def exercise_belongs_to_household
      return unless exercise && workout_block&.workout_template
      return if exercise.household_id == workout_block.workout_template.household_id

      errors.add(:exercise, "must belong to this household")
    end
end
