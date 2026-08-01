class Person::Today
  Item = Data.define(:kind, :record, :title, :description, :status, :destination)
  Section = Data.define(:key, :title, :description, :items)

  attr_reader :household, :person, :date, :activity_day, :sections, :shopping_list

  class << self
    def current(household:, person:)
      new(household: household, person: person, date: Date.current)
    end
  end

  def initialize(household:, person:, date:)
    @household = household
    @person = household.people.find(person.id)
    @date = date
    @activity_day = ActivityDay.new(household: household, person: @person, date: date)
    @shopping_list = ShoppingList.existing_for(household:, date:)
    @sections = build_sections.freeze
  end

  def unchecked_shopping_count
    shopping_list&.unchecked_count.to_i
  end

  private
    def build_sections
      planned_meals = household.planned_meals
        .during(date..date)
        .visible_to(person)
        .where.not(id: person.meals.where.not(planned_meal_id: nil).select(:planned_meal_id))
        .includes(:person, :recipe)
        .order(:planned_on, :created_at)
        .to_a
      meals = person.meals
        .during(date..date)
        .includes(meal_items: [ :recipe, :ingredient ])
        .order(:eaten_on, :created_at)
        .to_a

      up_next = planned_meals.map do |meal|
        Item.new(
          kind: :planned_meal,
          record: meal,
          title: meal.recipe.title,
          description: meal.person ? "Planned for #{meal.person.name}" : "Planned for the household",
          status: :planned,
          destination: meal.recipe
        )
      end
      up_next.concat(activity_day.up_next)

      completed = meals.map do |meal|
        Item.new(
          kind: :meal,
          record: meal,
          title: meal.description,
          description: "Recorded meal · #{meal.meal_items.size} #{'item'.pluralize(meal.meal_items.size)}",
          status: :logged,
          destination: meal
        )
      end
      completed.concat(activity_day.done)

      [
        Section.new(key: :up_next, title: "Up next", description: "What is planned for today.", items: up_next.freeze),
        Section.new(key: :in_progress, title: "In progress", description: "Pick up where you left off.", items: activity_day.in_progress),
        Section.new(key: :done, title: "Done", description: "What you have logged today.", items: completed.freeze)
      ]
    end
end
