class TrainingSessionBlock < ApplicationRecord
  belongs_to :training_session
  has_many :training_session_exercises, -> { order(:position) }, dependent: :destroy

  accepts_nested_attributes_for :training_session_exercises, allow_destroy: true, reject_if: :all_blank

  enum :snapshot_block_kind, WorkoutBlock::BLOCK_KINDS.index_with(&:itself), prefix: true, validate: true
  enum :snapshot_dose_class, WorkoutBlock::DOSE_CLASSES.index_with(&:itself), prefix: true, validate: true

  validates :snapshot_title, presence: true
  validates :position, numericality: { only_integer: true, greater_than: 0 }
  validates :actual_duration_seconds,
    numericality: { only_integer: true, greater_than: 0 },
    allow_nil: true

  def add_exercise
    training_session_exercises.build(
      position: active_exercises.size + 1,
      snapshot_performance_kind: "reps",
      snapshot_dose_class: snapshot_dose_class
    ).add_set
    normalize_positions
  end

  def remove_exercise(index)
    training_session_exercises.load_target
    record = training_session_exercises.target.fetch(Integer(index))
    record.persisted? ? record.mark_for_destruction : training_session_exercises.delete(record)
    normalize_positions
  rescue ArgumentError, IndexError
    raise ArgumentError, "Invalid performed exercise row."
  end

  def exercise_at(index)
    training_session_exercises.load_target
    training_session_exercises.target.fetch(Integer(index)).tap do |exercise|
      raise ArgumentError if exercise.marked_for_destruction?
    end
  rescue ArgumentError, IndexError
    raise ArgumentError, "Invalid performed exercise row."
  end

  def normalize_positions
    active_exercises.each.with_index(1) do |exercise, position|
      exercise.position = position
      exercise.normalize_positions
    end
    self
  end

  def ensure_form_rows
    add_exercise if active_exercises.empty?
    active_exercises.each(&:ensure_form_rows)
    self
  end

  def active_exercises
    training_session_exercises.load_target
    training_session_exercises.target.reject(&:marked_for_destruction?)
  end
end
