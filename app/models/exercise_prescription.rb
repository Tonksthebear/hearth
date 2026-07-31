class ExercisePrescription < ApplicationRecord
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
  validate :rep_range_is_ordered
  validate :primary_target_matches_performance_kind
  validate :target_distance_unit_matches_amount
  validate :target_count_unit_matches_count
  validate :heart_rate_target_is_complete_and_ordered
  validate :exercise_belongs_to_household

  def effective_dose_class
    dose_class.presence || workout_block.dose_class
  end

  def target_summary
    primary = case performance_kind
    when "reps" then "#{[ rep_min, rep_max ].compact.join("–")} reps"
    when "duration" then "#{work_seconds} sec"
    when "distance" then "#{target_distance_amount.to_f.to_fs(:delimited)} #{target_distance_unit}"
    when "count" then "#{target_count} #{target_count_unit}"
    when "interval" then "#{work_seconds} sec work / #{rest_seconds} sec recovery"
    end
    "#{sets_count} #{performance_kind == "interval" ? "rounds" : "rows"} · #{primary}"
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
    def rep_range_is_ordered
      errors.add(:rep_max, "must be at least the minimum reps") if rep_min && rep_max && rep_max < rep_min
    end

    def primary_target_matches_performance_kind
      case performance_kind
      when "reps"
        errors.add(:base, "Specify a rep target.") if rep_min.blank? && rep_max.blank?
      when "duration"
        errors.add(:work_seconds, "is required for duration work") if work_seconds.blank?
      when "distance"
        errors.add(:target_distance_amount, "is required for distance work") if target_distance_amount.blank?
      when "count"
        errors.add(:target_count, "is required for count work") if target_count.blank?
      when "interval"
        errors.add(:work_seconds, "is required for intervals") if work_seconds.blank?
        errors.add(:rest_seconds, "is required for intervals") if rest_seconds.blank?
      end
    end

    def target_distance_unit_matches_amount
      return if target_distance_amount.present? == target_distance_unit.present?
      errors.add(:target_distance_unit, "must be provided with target distance")
    end

    def target_count_unit_matches_count
      return if target_count.present? == target_count_unit.present?
      errors.add(:target_count_unit, "must be provided with target count")
    end

    def heart_rate_target_is_complete_and_ordered
      values_present = target_heart_rate_min.present? || target_heart_rate_max.present?
      errors.add(:target_heart_rate_unit, "must be provided with a heart-rate target") if values_present && target_heart_rate_unit.blank?
      errors.add(:target_heart_rate_unit, "requires a heart-rate target") if target_heart_rate_unit.present? && !values_present
      if target_heart_rate_min && target_heart_rate_max && target_heart_rate_max < target_heart_rate_min
        errors.add(:target_heart_rate_max, "must be at least the minimum heart rate")
      end
    end

    def exercise_belongs_to_household
      return unless exercise && workout_block&.workout_template
      return if exercise.household_id == workout_block.workout_template.household_id

      errors.add(:exercise, "must belong to this household")
    end
end
