class TrainingSession < ApplicationRecord
  belongs_to :household
  belongs_to :person
  belongs_to :workout_template, optional: true
  has_many :training_session_blocks, -> { order(:position) }, dependent: :destroy

  accepts_nested_attributes_for :training_session_blocks, allow_destroy: true, reject_if: :all_blank

  scope :during, ->(date_range) { where(performed_on: date_range) }
  scope :completed, -> { where.not(completed_at: nil) }
  scope :draft, -> { where(completed_at: nil) }

  validates :snapshot_title, :performed_on, :started_at, presence: true
  validate :person_belongs_to_household
  validate :template_belongs_to_household

  class << self
    def start_from(template:, person:, performed_on: Date.current)
      raise ActiveRecord::RecordNotFound unless template.household_id == person.household_id

      transaction do
        session = person.training_sessions.new(
          household: person.household,
          workout_template: template,
          snapshot_title: template.title,
          snapshot_provenance_status: template.provenance_status,
          snapshot_source_name: template.source_name,
          snapshot_source_url: template.source_url,
          performed_on: performed_on,
          started_at: Time.current
        )

        template.workout_blocks.includes(exercise_prescriptions: :exercise).each do |block|
          session_block = session.training_session_blocks.build(
            position: block.position,
            snapshot_title: block.title,
            snapshot_block_kind: block.block_kind,
            snapshot_dose_class: block.dose_class,
            snapshot_planned_duration_minutes: block.planned_duration_minutes,
            actual_duration_seconds: block.planned_duration_minutes&.*(60),
            notes: block.notes
          )

          block.exercise_prescriptions.each do |prescription|
            exercise = prescription.exercise
            session_exercise = session_block.training_session_exercises.build(
              exercise: exercise,
              position: prescription.position,
              snapshot_name: exercise.name,
              snapshot_modality: exercise.modality,
              snapshot_movement_pattern: exercise.movement_pattern,
              snapshot_equipment: exercise.equipment,
              snapshot_guidance: exercise.guidance,
              snapshot_entry_kind: prescription.entry_kind,
              snapshot_dose_class: prescription.effective_dose_class,
              snapshot_sets_count: prescription.sets_count,
              snapshot_rep_min: prescription.rep_min,
              snapshot_rep_max: prescription.rep_max,
              snapshot_work_seconds: prescription.work_seconds,
              snapshot_rest_seconds: prescription.rest_seconds,
              snapshot_target_rpe: prescription.target_rpe,
              snapshot_target_rir: prescription.target_rir,
              snapshot_load_guidance: prescription.load_guidance,
              notes: prescription.notes
            )

            prescription.sets_count.times do |index|
              session_exercise.training_sets.build(
                position: index + 1,
                entry_kind: prescription.entry_kind,
                dose_class: prescription.effective_dose_class
              )
            end
          end
        end

        session.save!
        session
      end
    end

    def build_ad_hoc(person:, performed_on: Date.current)
      new(
        household: person.household,
        person: person,
        snapshot_title: "Ad hoc workout",
        performed_on: performed_on,
        started_at: Time.current
      ).tap(&:add_block)
    end
  end

  def complete!
    raise ActiveRecord::RecordInvalid, self if completed?

    transaction do
      validate_completion_graph
      raise ActiveRecord::RecordInvalid, self if errors.any?

      update!(completed_at: Time.current)
    end
  end

  def completed?
    completed_at.present?
  end

  def add_block
    training_session_blocks.build(
      position: active_blocks.size + 1,
      snapshot_title: "Workout block",
      snapshot_block_kind: "other",
      snapshot_dose_class: "none"
    ).add_exercise
    normalize_positions
  end

  def remove_block(index)
    remove_nested_record(training_session_blocks, index, "performed block")
    normalize_positions
  end

  def add_exercise(block_index)
    block_at(block_index).add_exercise
    normalize_positions
  end

  def remove_exercise(coordinate)
    block_index, exercise_index = parse_coordinate(coordinate, 2)
    block_at(block_index).remove_exercise(exercise_index)
    normalize_positions
  end

  def add_set(coordinate)
    block_index, exercise_index = parse_coordinate(coordinate, 2)
    block_at(block_index).exercise_at(exercise_index).add_set
    normalize_positions
  end

  def remove_set(coordinate)
    block_index, exercise_index, set_index = parse_coordinate(coordinate, 3)
    block_at(block_index).exercise_at(exercise_index).remove_set(set_index)
    normalize_positions
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

  private
    def active_blocks
      training_session_blocks.load_target
      training_session_blocks.target.reject(&:marked_for_destruction?)
    end

    def block_at(index)
      training_session_blocks.load_target
      training_session_blocks.target.fetch(Integer(index)).tap do |block|
        raise ArgumentError if block.marked_for_destruction?
      end
    rescue ArgumentError, IndexError
      raise ArgumentError, "Invalid performed block row."
    end

    def parse_coordinate(value, count)
      parts = value.to_s.split(":")
      raise ArgumentError unless parts.size == count

      parts.map { |part| Integer(part) }
    rescue ArgumentError
      raise ArgumentError, "Invalid performed workout row."
    end

    def remove_nested_record(association, index, label)
      association.load_target
      record = association.target.fetch(Integer(index))
      record.persisted? ? record.mark_for_destruction : association.delete(record)
      self
    rescue ArgumentError, IndexError
      raise ArgumentError, "Invalid #{label} row."
    end

    def validate_completion_graph
      errors.clear
      errors.add(:base, "Add at least one performed block.") if active_blocks.empty?

      active_blocks.each do |block|
        if block.actual_duration_seconds.blank?
          errors.add(:base, "#{block.snapshot_title} requires an actual duration.")
        end

        exercises = block.active_exercises
        errors.add(:base, "#{block.snapshot_title} requires an exercise.") if exercises.empty?

        exercises.each do |exercise|
          sets = exercise.active_sets
          errors.add(:base, "#{exercise.snapshot_name} requires at least one set or interval.") if sets.empty?

          sets.each do |set|
            errors.add(:base, "#{exercise.snapshot_name} set #{set.position} must be completed.") unless set.completed?
            unless set.performance_measurement?
              errors.add(:base, "#{exercise.snapshot_name} set #{set.position} requires reps, duration, or distance.")
            end
            if set.interval? && set.duration_seconds.blank?
              errors.add(:base, "#{exercise.snapshot_name} interval #{set.position} requires a duration.")
            end
          end
        end

        classified_seconds = exercises.sum do |exercise|
          exercise.active_sets.select(&:completed?).sum do |set|
            %w[zone2 vigorous].include?(set.dose_class) ? set.duration_seconds.to_i : 0
          end
        end
        if block.actual_duration_seconds && classified_seconds > block.actual_duration_seconds
          errors.add(:base, "#{block.snapshot_title} classified work exceeds its actual duration.")
        end
      end
    end

    def person_belongs_to_household
      errors.add(:person, "must belong to this household") if person && person.household_id != household_id
    end

    def template_belongs_to_household
      return unless workout_template
      errors.add(:workout_template, "must belong to this household") if workout_template.household_id != household_id
    end
end
