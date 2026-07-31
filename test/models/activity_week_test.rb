require "test_helper"

class ActivityWeekTest < ActiveSupport::TestCase
  test "builds Monday through Sunday with navigation and person isolation" do
    travel_to Time.zone.local(2026, 7, 30, 12) do
      week = ActivityWeek.for(household: households(:home), person: people(:one), date: "2026-07-30")

      assert_equal Date.new(2026, 7, 27), week.start_date
      assert_equal Date.new(2026, 8, 2), week.end_date
      assert_equal 7, week.days.size
      assert_equal Date.new(2026, 7, 20), week.previous_date
      assert_equal Date.new(2026, 8, 3), week.next_date
      assert_predicate week, :includes_today?
      refute week.days.flat_map(&:up_next).any? { |item| item.record == planned_workouts(:sam_balanced) }
      refute week.days.flat_map(&:up_next).any? { |item| item.record == planned_workouts(:future_balanced) }
    end
  end

  test "malformed date falls back to current week" do
    travel_to Time.zone.local(2026, 7, 30, 12) do
      week = ActivityWeek.for(household: households(:home), person: people(:one), date: "nope")

      assert_equal Date.new(2026, 7, 27), week.start_date
    end
  end

  test "bulk loading stays within an absolute query bound" do
    travel_to Time.zone.local(2026, 7, 30, 12) do
      3.times do |index|
        people(:one).planned_workouts.create!(
          household: households(:home),
          workout_template: workout_templates(:balanced),
          scheduled_on: Date.current + index.days
        )
      end

      assert_operator sql_queries {
        ActivityWeek.current(household: households(:home), person: people(:one)).days
      }, :<=, 14
    end
  end

  private
    def sql_queries(&block)
      count = 0
      callback = ->(_name, _start, _finish, _id, payload) do
        count += 1 unless payload[:name] == "SCHEMA" || payload[:cached]
      end
      ActiveSupport::Notifications.subscribed(callback, "sql.active_record", &block)
      count
    end
end
