class TrainingSessionExercise < ApplicationRecord
  belongs_to :training_session_block
  belongs_to :exercise, optional: true
  has_many :training_sets, -> { order(:position) }, dependent: :destroy

  accepts_nested_attributes_for :training_sets, allow_destroy: true, reject_if: :all_blank

  enum :snapshot_modality, Exercise::MODALITIES.index_with(&:itself), prefix: true, validate: true
  enum :snapshot_movement_pattern, Exercise::MOVEMENT_PATTERNS.index_with(&:itself), prefix: true, validate: true
  enum :snapshot_entry_kind, ExercisePrescription::ENTRY_KINDS.index_with(&:itself), prefix: true, validate: true
  enum :snapshot_dose_class, WorkoutBlock::DOSE_CLASSES.index_with(&:itself), prefix: true, validate: true

  before_validation :copy_catalog_snapshot, if: :exercise_id_changed?

  validates :snapshot_name, presence: true
  validates :position, numericality: { only_integer: true, greater_than: 0 }
  validate :exercise_belongs_to_household

  def add_set
    training_sets.build(
      position: active_sets.size + 1,
      entry_kind: snapshot_entry_kind,
      dose_class: snapshot_dose_class
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
