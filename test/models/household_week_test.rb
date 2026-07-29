require "test_helper"

class HouseholdWeekTest < ActiveSupport::TestCase
  WEEK_START = Date.new(2026, 7, 27)

  test "normalizes dates and exposes stable week navigation" do
    travel_to Time.zone.local(2026, 7, 27, 12) do
      prepare_household_week_habits

      current = HouseholdWeek.for(household: households(:home), person: people(:one), date: nil)
      explicit = HouseholdWeek.for(household: households(:home), person: people(:one), date: "2026-07-29")

      assert_equal WEEK_START, current.start_date
      assert_equal WEEK_START, explicit.start_date
      assert_equal Date.new(2026, 8, 2), explicit.end_date
      assert_equal Date.new(2026, 7, 20), explicit.previous_date
      assert_equal Date.new(2026, 8, 3), explicit.next_date
      assert_equal WEEK_START, explicit.logging_date
      assert_equal "2026-07-27", explicit.to_param
    end
  end

  test "keeps household plans complete and person activity isolated inside the week" do
    travel_to Time.zone.local(2026, 7, 27, 12) do
      prepare_household_week_habits
      week = HouseholdWeek.for(household: households(:home), person: people(:one), date: "2026-07-29")

      assert_equal(
        %w[shared_target_week alex_target_week sam_target_week shared_soup_target_week].map { |name| planned_meals(name).id },
        week.planned_meals.map(&:id)
      )
      assert_not_includes week.planned_meals, planned_meals(:adjacent_week)
      assert_equal [ nil, people(:one).id, people(:two).id, nil ], week.planned_meals.map(&:person_id)

      alex = summary_for(week, people(:one))
      sam = summary_for(week, people(:two))
      jordan = summary_for(week, people(:without_login))

      assert_equal [ meal_logs(:alex_recipe_target_week), meal_logs(:alex_ad_hoc_target_week) ], alex.meal_logs
      assert_equal [ meal_logs(:sam_recipe_target_week) ], sam.meal_logs
      assert_empty jordan.meal_logs
      assert_equal [ training_sessions(:draft), training_sessions(:completed_sunday) ], alex.training_sessions
      assert_equal [ training_sessions(:other_person) ], sam.training_sessions
      assert_empty jordan.training_sessions
      assert_not_includes alex.training_sessions, training_sessions(:following_monday)
    end
  end

  test "reuses recovery statuses across active and historical habits" do
    travel_to Time.zone.local(2026, 7, 27, 12) do
      prepare_household_week_habits
      week = HouseholdWeek.for(household: households(:home), person: people(:one), date: WEEK_START)
      alex = summary_for(week, people(:one))
      sam = summary_for(week, people(:two))

      assert_equal :checked, status_for(alex, habits(:water), Date.new(2026, 7, 28))
      assert_equal :not_checked, status_for(alex, habits(:water), Date.new(2026, 7, 29))
      assert_not_includes habit_for(alex, habits(:water)).entry.check_ins, Date.new(2026, 8, 3)
      assert_equal :not_scheduled, status_for(alex, habits(:sauna), Date.new(2026, 8, 2))
      assert_equal :checked, status_for(alex, habits(:lights_out), Date.new(2026, 7, 30))
      assert_equal :no_record, status_for(alex, habits(:lights_out), Date.new(2026, 7, 31))
      assert_predicate habit_for(alex, habits(:lights_out)), :history_only?
      assert_equal :checked, status_for(sam, habits(:movement), Date.new(2026, 7, 29))
    end
  end

  test "default week follows the controlled current date" do
    travel_to Time.zone.local(2026, 8, 31, 12) do
      prepare_household_week_habits
      week = HouseholdWeek.for(household: households(:home), person: people(:one), date: nil)

      assert_equal Date.new(2026, 8, 31), week.start_date
      assert_empty week.planned_meals
      assert_empty summary_for(week, people(:one)).meal_logs
      assert_empty summary_for(week, people(:one)).training_sessions
    end
  end

  test "fully materialized query count is bounded and constant as people are added" do
    travel_to Time.zone.local(2026, 7, 27, 12) do
      prepare_household_week_habits
      household = households(:home)
      person = people(:one)

      assert_queries_count(6) do
        materialize(HouseholdWeek.for(household: household, person: person, date: WEEK_START))
      end
      assert_operator 6, :<=, 12

      household.people.create!(name: "Taylor")

      assert_queries_count(6) do
        materialize(HouseholdWeek.for(household: household, person: person, date: WEEK_START))
      end
    end
  end

  private
    def summary_for(week, person)
      week.person_summaries.find { |summary| summary.person == person }
    end

    def habit_for(summary, habit)
      summary.habits.find { |habit_summary| habit_summary.habit == habit }
    end

    def status_for(summary, habit, date)
      habit_for(summary, habit).days.find { |day| day.date == date }.status
    end

    def materialize(week)
      week.planned_meals.each { |plan| [ plan.recipe.title, plan.person&.name, plan.planned_on ] }
      week.person_summaries.each do |summary|
        summary.person.name
        summary.meal_logs.each { |meal_log| [ meal_log.description, meal_log.eaten_on ] }
        summary.training_sessions.each { |session| [ session.snapshot_title, session.performed_on, session.completed? ] }
        summary.habits.each do |habit_summary|
          [ habit_summary.habit.name, habit_summary.history_only? ]
          habit_summary.days.each { |day| [ day.date, day.status ] }
        end
      end
    end
end
