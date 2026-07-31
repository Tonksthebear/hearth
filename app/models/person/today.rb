class Person::Today
  Item = Data.define(:kind, :record, :title, :description, :status, :destination)
  Section = Data.define(:key, :title, :description, :items)

  attr_reader :household, :person, :date, :sections

  class << self
    def current(household:, person:)
      new(household: household, person: person, date: Date.current)
    end
  end

  def initialize(household:, person:, date:)
    @household = household
    @person = household.people.find(person.id)
    @date = date
    @sections = build_sections.freeze
  end

  private
    def build_sections
      planned_meals = household.planned_meals
        .during(date..date)
        .visible_to(person)
        .includes(:person, :recipe)
        .order(:planned_on, :created_at)
        .to_a
      meal_logs = person.meal_logs
        .during(date..date)
        .includes(:recipe)
        .order(:eaten_on, :created_at)
        .to_a
      sessions = person.training_sessions
        .during(date..date)
        .order(:started_at, :created_at)
        .to_a
      recovery = RecoveryDay.current(household: household, person: person)

      todo = planned_meals.map do |meal|
        Item.new(
          kind: :planned_meal,
          record: meal,
          title: meal.recipe.title,
          description: meal.person ? "Planned for #{meal.person.name}" : "Planned for the household",
          status: :planned,
          destination: meal.recipe
        )
      end
      todo.concat recovery.actionable_entries.filter_map { |entry| habit_item(entry) }

      in_progress = sessions.reject(&:completed?).map do |session|
        Item.new(
          kind: :training_session,
          record: session,
          title: session.snapshot_title,
          description: "Workout started #{session.started_at.to_fs(:time)}",
          status: :in_progress,
          destination: [ :edit, session ]
        )
      end

      completed = meal_logs.map do |meal_log|
        Item.new(
          kind: :meal_log,
          record: meal_log,
          title: meal_log.description,
          description: "Meal logged",
          status: :logged,
          destination: meal_log.recipe
        )
      end
      completed.concat(sessions.select(&:completed?).map do |session|
        Item.new(
          kind: :training_session,
          record: session,
          title: session.snapshot_title,
          description: "Workout completed",
          status: :completed,
          destination: session
        )
      end)
      completed.concat recovery.actionable_entries.filter_map { |entry| completed_habit_item(entry, recovery) }

      [
        Section.new(key: :to_do, title: "To do", description: "What is planned for today.", items: todo.freeze),
        Section.new(key: :in_progress, title: "In progress", description: "Pick up where you left off.", items: in_progress.freeze),
        Section.new(key: :complete, title: "Complete", description: "What you have logged today.", items: completed.freeze)
      ]
    end

    def habit_item(entry)
      return if entry.check_in_on(date)

      Item.new(
        kind: entry.habit.habit_metrics.empty? ? :simple_habit : :measured_habit,
        record: entry.person_habit,
        title: entry.habit.name,
        description: entry.habit.description,
        status: :to_do,
        destination: nil
      )
    end

    def completed_habit_item(entry, _recovery)
      return unless entry.check_in_on(date)

      Item.new(
        kind: :habit_check_in,
        record: entry.check_in_on(date),
        title: entry.habit.name,
        description: "Habit checked off",
        status: :completed,
        destination: nil
      )
    end
end
