class HouseholdWeek
  HabitDay = Data.define(:date, :status)

  HabitSummary = Data.define(:entry, :days) do
    delegate :habit, :history_only?, to: :entry
  end

  PersonSummary = Data.define(:person, :meals, :training_sessions, :habits)

  attr_reader :household, :person, :start_date, :planned_meals, :people, :person_summaries

  class << self
    def current(household:, person:)
      new(household: household, person: person, date: Date.current)
    end

    def for(household:, person:, date:)
      new(household: household, person: person, date: Date.iso8601(date.to_s))
    rescue ArgumentError, Date::Error
      current(household: household, person: person)
    end
  end

  def initialize(household:, person:, date:)
    @household = household
    @person = person
    @start_date = date.beginning_of_week(:monday)
    @people = household.people.order(:name).to_a.freeze
    @planned_meals = load_planned_meals.freeze
    @person_summaries = load_person_summaries.freeze
  end

  def end_date
    start_date + 6.days
  end

  def date_range
    start_date..end_date
  end

  def days
    @days ||= date_range.to_a.freeze
  end

  def previous_date
    start_date - 7.days
  end

  def next_date
    start_date + 7.days
  end

  def logging_date
    Date.current.in?(date_range) ? Date.current : start_date
  end

  def to_param
    start_date.iso8601
  end

  private
    def load_planned_meals
      household.planned_meals
        .during(date_range)
        .eager_load(:person, :recipe)
        .order(:planned_on, :created_at)
        .to_a
    end

    def load_person_summaries
      meals_by_person = household.meals
        .during(date_range)
        .eager_load(meal_items: [ :recipe, :ingredient ])
        .order(:eaten_on, :created_at)
        .to_a
        .group_by(&:person_id)
      sessions_by_person = household.training_sessions
        .during(date_range)
        .order(:performed_on, :started_at)
        .to_a
        .group_by(&:person_id)
      habits_by_person = load_habits.group_by { |summary| summary.entry.person_habit.person_id }

      people.map do |household_person|
        PersonSummary.new(
          person: household_person,
          meals: meals_by_person.fetch(household_person.id, []).freeze,
          training_sessions: sessions_by_person.fetch(household_person.id, []).freeze,
          habits: habits_by_person.fetch(household_person.id, []).freeze
        )
      end
    end

    def load_habits
      configurations = PersonHabit
        .where(person_id: people.map(&:id))
        .eager_load(:habit)
        .in_display_order
        .to_a
      check_ins_by_configuration = HabitCheckIn
        .where(person_habit_id: configurations.map(&:id), checked_on: date_range)
        .to_a
        .group_by(&:person_habit_id)

      configurations.filter_map do |configuration|
        check_ins = check_ins_by_configuration.fetch(configuration.id, []).index_by(&:checked_on)
        next unless configuration.active? || check_ins.any?

        entry = RecoveryDay::Entry.new(person_habit: configuration, check_ins: check_ins)
        HabitSummary.new(
          entry: entry,
          days: days.map { |date| HabitDay.new(date: date, status: entry.status_on(date)) }.freeze
        )
      end
    end
end
