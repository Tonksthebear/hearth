class RecoveryDay
  Entry = Data.define(:person_habit, :check_ins) do
    delegate :habit, to: :person_habit

    def check_in_on(date)
      check_ins[date]
    end

    def status_on(date)
      return :checked if check_in_on(date)
      return :no_record unless person_habit.active?

      person_habit.scheduled_on?(date) ? :not_checked : :not_scheduled
    end

    def history_only?
      !person_habit.active?
    end
  end

  attr_reader :household, :person, :date, :dates, :entries

  class << self
    def current(household:, person:, check_in: nil)
      new(household: household, person: person, date: Date.current, check_in: check_in)
    end
  end

  def initialize(household:, person:, date:, check_in: nil)
    @household = household
    @person = person
    @date = date
    @dates = (date - 6.days..date).to_a.reverse.freeze
    @submitted_check_in = check_in
    @entries = load_entries.freeze
  end

  def actionable_entries
    entries.select { |entry| entry.person_habit.active? && entry.person_habit.scheduled_on?(date) }
  end

  def check_in_for(entry)
    submitted = @submitted_check_in
    check_in = if submitted&.person_habit_id == entry.person_habit.id
      submitted
    else
      entry.check_in_on(date) || entry.person_habit.habit_check_ins.build(checked_on: date)
    end
    check_in.ensure_measurement_rows
  end

  private
    def load_entries
      configurations = person.person_habits
        .includes(habit: :habit_metrics, person_habit_metrics: :habit_metric)
        .in_display_order
        .to_a
      check_ins = HabitCheckIn
        .where(person_habit_id: configurations.map(&:id), checked_on: dates)
        .includes(habit_check_in_measurements: :habit_metric)
        .group_by(&:person_habit_id)

      configurations.filter_map do |configuration|
        by_date = check_ins.fetch(configuration.id, []).index_by(&:checked_on)
        next unless configuration.active? || by_date.any?

        Entry.new(person_habit: configuration, check_ins: by_date)
      end
    end
end
