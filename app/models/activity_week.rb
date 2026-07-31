class ActivityWeek
  attr_reader :household, :person, :start_date, :days, :training_week

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
    @person = household.people.find(person.id)
    @start_date = date.beginning_of_week(:monday)
    @training_week = TrainingWeek.new(household: household, person: @person, date: start_date)
    load_days
  end

  def end_date
    start_date + 6.days
  end

  def date_range
    start_date..end_date
  end

  def previous_date
    start_date - 7.days
  end

  def next_date
    start_date + 7.days
  end

  def current_date
    Date.current
  end

  def includes_today?
    date_range.cover?(current_date)
  end

  def to_param
    start_date.iso8601
  end

  private
    def load_days
      sessions = person.training_sessions
        .during(date_range)
        .includes(:workout_template)
        .order(:performed_on, :started_at, :created_at)
        .to_a
      plans = person.planned_workouts
        .where(scheduled_on: date_range)
        .or(person.planned_workouts.where(training_session_id: sessions.map(&:id)))
        .includes(:workout_template, :training_session)
        .order(:scheduled_on, :created_at)
        .to_a
      configurations = person.person_habits
        .active
        .includes(habit: :habit_metrics)
        .in_display_order
        .to_a
      check_ins = HabitCheckIn
        .where(person_habit_id: configurations.map(&:id), checked_on: date_range)
        .includes(:person_habit)
        .to_a

      @days = date_range.map do |date|
        ActivityDay.new(
          household: household,
          person: person,
          date: date,
          planned_workouts: plans,
          training_sessions: sessions.select { |session| session.performed_on == date },
          person_habits: configurations,
          habit_check_ins: check_ins.select { |check_in| check_in.checked_on == date }
        )
      end.freeze
    end
end
