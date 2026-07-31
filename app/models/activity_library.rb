class ActivityLibrary
  Section = Data.define(:key, :title, :description, :records)

  attr_reader :household, :person, :sections

  def initialize(household:, person:)
    @household = household
    @person = household.people.find(person.id)
    @sections = [
      Section.new(
        key: :workout_templates,
        title: "Workout templates",
        description: "Reusable plans for structured training sessions.",
        records: household.workout_templates.order(:title).to_a.freeze
      ),
      Section.new(
        key: :exercises,
        title: "Exercises",
        description: "The household movement catalog used by workout templates.",
        records: household.exercises.order(:name).to_a.freeze
      ),
      Section.new(
        key: :habits,
        title: "Habits",
        description: "Household recovery and daily practice definitions.",
        records: household.habits.order(:name).to_a.freeze
      ),
      Section.new(
        key: :recovery,
        title: "#{@person.name}'s recovery routines",
        description: "Scheduled habit configurations and recent adherence.",
        records: @person.person_habits.includes(:habit).in_display_order.to_a.freeze
      )
    ].freeze
  end
end
