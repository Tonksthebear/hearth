class ActivityDay
  Item = Data.define(:kind, :record, :title, :description, :status, :destination)
  Section = Data.define(:key, :title, :description, :items)

  attr_reader :household, :person, :date, :up_next, :in_progress, :done, :sections

  def initialize(household:, person:, date:, planned_workouts: nil, training_sessions: nil, person_habits: nil, habit_check_ins: nil)
    @household = household
    @person = household.people.find(person.id)
    @date = date
    @training_sessions = training_sessions || load_training_sessions
    @planned_workouts = planned_workouts || load_planned_workouts
    @person_habits = person_habits || load_person_habits
    @habit_check_ins = habit_check_ins || load_habit_check_ins

    build_items
  end

  def today?
    date == Date.current
  end

  private
    def load_training_sessions
      person.training_sessions
        .during(date..date)
        .includes(:workout_template)
        .order(:started_at, :created_at)
        .to_a
    end

    def load_planned_workouts
      person.planned_workouts
        .where(scheduled_on: date)
        .or(person.planned_workouts.where(training_session_id: @training_sessions.map(&:id)))
        .includes(:workout_template, :training_session)
        .order(:scheduled_on, :created_at)
        .to_a
    end

    def load_person_habits
      person.person_habits
        .active
        .includes(habit: :habit_metrics)
        .in_display_order
        .to_a
    end

    def load_habit_check_ins
      HabitCheckIn
        .where(person_habit_id: @person_habits.map(&:id), checked_on: date)
        .includes(:person_habit)
        .to_a
    end

    def build_items
      linked_session_ids = @planned_workouts.filter_map(&:training_session_id).to_set
      plan_items = @planned_workouts.filter_map { |plan| plan_item(plan) }
      session_items = @training_sessions
        .reject { |session| linked_session_ids.include?(session.id) }
        .map { |session| session_item(session) }
      habit_items = @person_habits.filter_map { |configuration| habit_item(configuration) }
      items = plan_items + session_items + habit_items

      @up_next = items.select { |item| item.status == :planned }.freeze
      @in_progress = items.select { |item| item.status == :in_progress }.freeze
      @done = items.select { |item| %i[completed skipped checked].include?(item.status) }.freeze
      @sections = [
        Section.new(key: :up_next, title: "Up next", description: "Planned actions for this day.", items: up_next),
        Section.new(key: :in_progress, title: "In progress", description: "Work that has already started.", items: in_progress),
        Section.new(key: :done, title: "Done", description: "Completed and skipped outcomes.", items: done)
      ].freeze
    end

    def plan_item(plan)
      if plan.training_session
        return unless plan.training_session.performed_on == date

        Item.new(
          kind: :workout,
          record: plan,
          title: plan.training_session.snapshot_title,
          description: plan.training_session.completed? ? "Workout completed" : "Workout started",
          status: plan.status,
          destination: plan.training_session.completed? ? plan.training_session : [ :edit, plan.training_session ]
        )
      elsif plan.scheduled_on == date
        Item.new(
          kind: :workout,
          record: plan,
          title: plan.workout_template.title,
          description: plan.skipped_at? ? plan.skip_reason.presence || "Workout skipped" : "Workout planned",
          status: plan.status,
          destination: plan.workout_template
        )
      end
    end

    def session_item(session)
      Item.new(
        kind: :workout,
        record: session,
        title: session.snapshot_title,
        description: session.completed? ? "Workout completed" : "Workout started",
        status: session.completed? ? :completed : :in_progress,
        destination: session.completed? ? session : [ :edit, session ]
      )
    end

    def habit_item(configuration)
      return unless configuration.scheduled_on?(date)

      check_in = @habit_check_ins.find { |record| record.person_habit_id == configuration.id }
      measured = configuration.habit.habit_metrics.any?
      Item.new(
        kind: check_in ? :habit_check_in : (measured ? :measured_habit : :simple_habit),
        record: check_in || configuration,
        title: configuration.habit.name,
        description: habit_description(configuration, check_in:, measured:),
        status: check_in ? :checked : :planned,
        destination: nil
      )
    end

    def habit_description(configuration, check_in:, measured:)
      return "Habit checked off" if check_in

      configuration.habit.description.presence || (measured ? "Record a value for this habit" : "Daily habit")
    end
end
