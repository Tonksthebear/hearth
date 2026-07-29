class HabitCheckInMeasurement < ApplicationRecord
  include TypedHabitValue

  belongs_to :habit_check_in
  belongs_to :habit_metric

  validates :habit_metric_id, uniqueness: { scope: :habit_check_in_id }
  validate :metric_belongs_to_checked_habit

  private
    def metric_belongs_to_checked_habit
      return unless habit_check_in && habit_metric
      errors.add(:habit_metric, "must belong to the checked habit") unless habit_metric.habit_id == habit_check_in.person_habit.habit_id
    end
end
