class PlannedWorkout < ApplicationRecord
  belongs_to :household
  belongs_to :person
  belongs_to :workout_template
  belongs_to :training_session, optional: true

  scope :skipped, -> { where.not(skipped_at: nil) }

  validates :scheduled_on, presence: true
  validates :training_session_id, uniqueness: true, allow_nil: true
  validates :skip_reason, length: { maximum: 240 }, allow_blank: true
  validate :person_belongs_to_household
  validate :template_belongs_to_household
  validate :session_matches_plan
  validate :skip_state_is_consistent

  before_destroy :ensure_removable

  def status
    return :skipped if skipped_at?
    return :planned unless training_session

    training_session.completed? ? :completed : :in_progress
  end

  def planned?
    status == :planned
  end

  def skippable?
    planned? && scheduled_on <= Date.current
  end

  def startable?
    planned? && scheduled_on <= Date.current
  end

  def start!
    with_lock do
      unless startable?
        errors.add(:base, "Only a due, planned workout can be started.")
        raise ActiveRecord::RecordInvalid, self
      end

      session = TrainingSession.start_from(
        template: workout_template,
        person: person,
        performed_on: Date.current
      )
      update!(training_session: session)
      session
    end
  end

  def reschedule!(scheduled_on:)
    with_lock do
      unless planned?
        errors.add(:base, "Only an unstarted planned workout can be rescheduled.")
        raise ActiveRecord::RecordInvalid, self
      end

      update!(scheduled_on: scheduled_on)
    end
  end

  def skip!(reason: nil)
    with_lock do
      unless skippable?
        errors.add(:base, "Only a due, unstarted workout can be skipped.")
        raise ActiveRecord::RecordInvalid, self
      end

      update!(skipped_at: Time.current, skip_reason: reason.presence)
    end
  end

  def restore!
    with_lock do
      unless status == :skipped
        errors.add(:base, "Only a skipped workout can be restored.")
        raise ActiveRecord::RecordInvalid, self
      end

      update!(skipped_at: nil, skip_reason: nil)
    end
  end

  private
    def ensure_removable
      return if destroyed_by_association || planned?

      errors.add(:base, "Only an unstarted planned workout can be removed.")
      throw :abort
    end

    def person_belongs_to_household
      return unless person && household

      errors.add(:person, "must belong to this household") unless person.household_id == household_id
    end

    def template_belongs_to_household
      return unless workout_template && household

      errors.add(:workout_template, "must belong to this household") unless workout_template.household_id == household_id
    end

    def session_matches_plan
      return unless training_session

      errors.add(:training_session, "must belong to this household") unless training_session.household_id == household_id
      errors.add(:training_session, "must belong to this person") unless training_session.person_id == person_id
      errors.add(:training_session, "must use this workout template") unless training_session.workout_template_id == workout_template_id
    end

    def skip_state_is_consistent
      errors.add(:skip_reason, "requires a skipped workout") if skip_reason.present? && skipped_at.blank?
      errors.add(:training_session, "cannot coexist with a skipped workout") if training_session && skipped_at?
    end
end
