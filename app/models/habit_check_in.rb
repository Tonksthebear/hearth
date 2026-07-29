class HabitCheckIn < ApplicationRecord
  belongs_to :person_habit
  has_many :habit_check_in_measurements, dependent: :destroy

  accepts_nested_attributes_for :habit_check_in_measurements

  validates :checked_on, presence: true, uniqueness: { scope: :person_habit_id }
  validate :measurement_set_matches_habit

  def ensure_measurement_rows
    existing_metric_ids = habit_check_in_measurements.map(&:habit_metric_id)
    person_habit.habit.habit_metrics.each do |metric|
      habit_check_in_measurements.build(habit_metric: metric) unless existing_metric_ids.include?(metric.id)
    end
    self
  end

  def recorded_measurements
    habit_check_in_measurements.select(&:persisted?)
  end

  private
    def measurement_set_matches_habit
      expected_ids = person_habit&.habit&.habit_metric_ids || []
      submitted_ids = habit_check_in_measurements.reject(&:marked_for_destruction?).map(&:habit_metric_id)
      return if submitted_ids.sort == expected_ids.sort

      errors.add(:habit_check_in_measurements, "must include each configured habit metric exactly once")
    end
end
