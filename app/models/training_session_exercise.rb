class TrainingSessionExercise < ApplicationRecord
  DIFFICULTIES = %w[too_easy about_right too_hard].freeze

  belongs_to :training_session_block
  belongs_to :exercise, optional: true
  has_many :training_sets, -> { order(:position) }, dependent: :destroy

  accepts_nested_attributes_for :training_sets, allow_destroy: true, reject_if: :all_blank

  enum :snapshot_modality, Exercise::MODALITIES.index_with(&:itself), prefix: true, validate: true
  enum :snapshot_movement_pattern, Exercise::MOVEMENT_PATTERNS.index_with(&:itself), prefix: true, validate: true
  enum :snapshot_performance_kind, ExercisePrescription::PERFORMANCE_KINDS.index_with(&:itself), prefix: true, validate: true
  enum :snapshot_dose_class, WorkoutBlock::DOSE_CLASSES.index_with(&:itself), prefix: true, validate: true
  enum :snapshot_target_distance_unit, ExercisePrescription::DISTANCE_UNITS.index_with(&:itself), prefix: true, validate: { allow_nil: true }
  enum :snapshot_target_count_unit, ExercisePrescription::COUNT_UNITS.index_with(&:itself), prefix: true, validate: { allow_nil: true }
  enum :snapshot_target_heart_rate_unit, ExercisePrescription::HEART_RATE_UNITS.index_with(&:itself), prefix: true, validate: { allow_nil: true }
  enum :difficulty, DIFFICULTIES.index_with(&:itself), validate: { allow_nil: true }

  before_validation :copy_catalog_snapshot, if: :exercise_id_changed?

  validates :snapshot_name, presence: true
  validates :position, numericality: { only_integer: true, greater_than: 0 }
  validate :exercise_belongs_to_household

  def add_set
    training_sets.build(
      position: active_sets.size + 1,
      dose_class: snapshot_dose_class,
      duration_seconds: %w[duration interval].include?(snapshot_performance_kind) ? snapshot_work_seconds : nil,
      rest_seconds: snapshot_performance_kind == "interval" ? snapshot_rest_seconds : nil
    )
    normalize_positions
  end

  def remove_set(index)
    training_sets.load_target
    record = training_sets.target.fetch(Integer(index))
    record.persisted? ? record.mark_for_destruction : training_sets.delete(record)
    normalize_positions
  rescue ArgumentError, IndexError
    raise ArgumentError, "Invalid training set row."
  end

  def normalize_positions
    active_sets.each.with_index(1) { |set, position| set.position = position }
    self
  end

  def ensure_form_rows
    add_set if active_sets.empty?
    self
  end

  def active_sets
    training_sets.load_target
    training_sets.target.reject(&:marked_for_destruction?)
  end

  def completion_ready?
    active_sets.present? && active_sets.all? { |set| set.completed? && set.valid? }
  end

  def sync_completed_at!
    session = training_session_block.training_session
    return if session.completed?

    value = completion_ready? ? (completed_at || Time.current) : nil
    persisted? ? update_column(:completed_at, value) : self.completed_at = value
  end

  def target_summary
    primary = case snapshot_performance_kind
    when "reps" then "#{[ snapshot_rep_min, snapshot_rep_max ].compact.join("–")} reps"
    when "duration" then "#{snapshot_work_seconds} sec"
    when "distance" then "#{snapshot_target_distance_amount.to_f.to_fs(:delimited)} #{snapshot_target_distance_unit}"
    when "count" then "#{snapshot_target_count} #{snapshot_target_count_unit}"
    when "interval" then "#{snapshot_work_seconds} sec work / #{snapshot_rest_seconds} sec recovery"
    end
    "#{snapshot_sets_count || active_sets.size} #{snapshot_performance_kind == "interval" ? "rounds" : "rows"} · #{primary}"
  end

  def feedback_summary
    [
      difficulty&.humanize,
      ("Soreness or pain noted: #{soreness_or_pain}" if soreness_or_pain.present?),
      ("Substitution: #{substitution}" if substitution.present?),
      ("Next time: #{next_time_adjustment}" if next_time_adjustment.present?)
    ].compact.join(" · ")
  end

  def cue_summary
    [
      ("per side" if snapshot_per_side?),
      snapshot_tempo_cue.presence,
      snapshot_load_guidance.presence,
      snapshot_heart_rate_summary,
      ("RPE #{snapshot_target_rpe.to_f.to_fs(:delimited)}" if snapshot_target_rpe),
      ("RIR #{snapshot_target_rir.to_f.to_fs(:delimited)}" if snapshot_target_rir)
    ].compact.join(" · ")
  end

  def snapshot_heart_rate_summary
    return if snapshot_target_heart_rate_min.blank? && snapshot_target_heart_rate_max.blank?
    value = [ snapshot_target_heart_rate_min, snapshot_target_heart_rate_max ].compact.join("–")
    "HR #{value} #{snapshot_target_heart_rate_unit == "percent_max" ? "% max" : "bpm"}"
  end

  private
    def copy_catalog_snapshot
      return unless exercise
      return unless exercise.household_id == training_session_block.training_session.household_id

      self.snapshot_name = exercise.name
      self.snapshot_modality = exercise.modality
      self.snapshot_movement_pattern = exercise.movement_pattern
      self.snapshot_equipment = exercise.equipment
      self.snapshot_guidance = exercise.guidance
    end

    def exercise_belongs_to_household
      return unless exercise
      return if exercise.household_id == training_session_block.training_session.household_id

      errors.add(:exercise, "must belong to this household")
    end
end
