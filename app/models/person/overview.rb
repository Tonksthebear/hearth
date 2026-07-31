class Person::Overview
  attr_reader :household, :person, :meal_week, :training_week, :recovery_day

  class << self
    def current(household:, person:)
      new(household: household, person: person, date: Date.current)
    end
  end

  def initialize(household:, person:, date:)
    @household = household
    @person = household.people.find(person.id)
    @meal_week = MealWeek.current(household: household, person: @person)
    @training_week = TrainingWeek.current(household: household, person: @person)
    @recovery_day = RecoveryDay.current(household: household, person: @person)

    materialize!
  end

  private
    def materialize!
      meal_week.planned_meals.to_a.freeze
      meal_week.meal_logs.to_a.freeze
      training_week.draft_sessions.to_a.freeze
      training_week.completed_sessions.to_a.freeze
      recovery_day.entries
    end
end
