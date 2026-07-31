class ActivityOverview
  Item = Data.define(:record, :title)
  Section = Data.define(:key, :title, :description, :records, :destination)

  attr_reader :household, :person, :training_week, :recovery_day, :sections

  class << self
    def current(household:, person:)
      new(household: household, person: person)
    end
  end

  def initialize(household:, person:)
    @household = household
    @person = household.people.find(person.id)
    @training_week = TrainingWeek.current(household: household, person: @person)
    @recovery_day = RecoveryDay.current(household: household, person: @person)

    @sections = [
      Section.new(
        key: :training,
        title: "Training",
        description: "This person's current workout week.",
        records: (training_week.draft_sessions.to_a + training_week.completed_sessions.to_a)
          .map { |session| Item.new(record: session, title: session.snapshot_title) }
          .freeze,
        destination: :training_week
      ),
      Section.new(
        key: :recovery,
        title: "Recovery",
        description: "Scheduled habits, measurements, and recent check-ins.",
        records: recovery_day.entries
          .map { |entry| Item.new(record: entry, title: entry.habit.name) }
          .freeze,
        destination: :recovery_day
      ),
      Section.new(
        key: :templates,
        title: "Workout templates",
        description: "Reusable workouts shared by the household.",
        records: household.workout_templates.order(:title)
          .map { |template| Item.new(record: template, title: template.title) }
          .freeze,
        destination: :workout_templates
      ),
      Section.new(
        key: :exercises,
        title: "Exercises",
        description: "The household exercise catalog.",
        records: household.exercises.order(:name)
          .map { |exercise| Item.new(record: exercise, title: exercise.name) }
          .freeze,
        destination: :exercises
      )
    ].freeze
  end
end
