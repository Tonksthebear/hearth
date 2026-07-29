module HouseholdWeekTestHelper
  def prepare_household_week_habits(household: households(:home))
    HabitCheckIn
      .where(person_habit_id: PersonHabit.where(person_id: household.people.select(:id)))
      .destroy_all

    create_habit_check_in(person_habits(:alex_water), Date.new(2026, 7, 28))
    create_habit_check_in(
      person_habits(:sam_movement),
      Date.new(2026, 7, 29),
      habit_metrics(:movement_duration) => { duration_value: 20 }
    )
    create_habit_check_in(
      person_habits(:alex_lights_out),
      Date.new(2026, 7, 30),
      habit_metrics(:lights_out_time) => { time_of_day_value: "22:15:00" }
    )
    create_habit_check_in(person_habits(:alex_water), Date.new(2026, 8, 3))
  end

  private
    def create_habit_check_in(person_habit, checked_on, measurements = {})
      person_habit.habit_check_ins.build(checked_on: checked_on).tap do |check_in|
        measurements.each do |metric, attributes|
          check_in.habit_check_in_measurements.build(attributes.merge(habit_metric: metric))
        end
        check_in.save!
      end
    end
end

ActiveSupport::TestCase.include HouseholdWeekTestHelper
