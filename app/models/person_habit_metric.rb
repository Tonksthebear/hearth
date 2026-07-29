class PersonHabitMetric < ApplicationRecord
  include TypedHabitValue

  belongs_to :person_habit
  belongs_to :habit_metric

  validates :habit_metric_id, uniqueness: { scope: :person_habit_id }
  validate :metric_belongs_to_configured_habit

  private
    def allow_blank_typed_value?
      true
    end

    def metric_belongs_to_configured_habit
      return unless person_habit && habit_metric
      errors.add(:habit_metric, "must belong to the configured habit") unless habit_metric.habit_id == person_habit.habit_id
    end
end
