class Person::Today
  Item = Data.define(:kind, :record, :title, :description, :status, :destination)
  Section = Data.define(:key, :title, :description, :items)
  Fact = Data.define(:key, :title, :value, :description, :tone)
  Summary = Data.define(:facts) do
    def empty?
      facts.empty?
    end
  end

  attr_reader :household, :person, :date, :activity_day, :sections, :shopping_list, :nutrition_summary, :summary

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
        .includes(meal_items: [ :recipe, :ingredient, :meal_item_nutrient_values ])
        .order(:eaten_on, :created_at)
        .to_a
      @nutrition_summary = Meal::NutritionSummary.new(meals)
      @summary = build_summary(planned_meals:, meals:)

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

    def build_summary(planned_meals:, meals:)
      activity_items = activity_day.up_next + activity_day.in_progress + activity_day.done
      return Summary.new(facts: [].freeze) if planned_meals.empty? && meals.empty? && activity_items.empty?

      attention_reasons = []
      skipped_workouts = activity_day.done.count { |item| item.kind == :workout && item.status == :skipped }
      attention_reasons << "#{skipped_workouts} skipped #{'workout'.pluralize(skipped_workouts)}" if skipped_workouts.positive?
      if meals.any? && %w[incomplete unavailable].include?(nutrition_summary.status)
        attention_reasons << "logged meal nutrition needs more detail"
      end

      facts = [
        Fact.new(
          key: :meals,
          title: "Meals".freeze,
          value: "#{meals.size} eaten · #{planned_meals.size} planned".freeze,
          description: meal_summary_description(meals).freeze,
          tone: :neutral
        ),
        Fact.new(
          key: :activities,
          title: "Activities and recovery".freeze,
          value: "#{activity_day.done.size} done · #{activity_day.in_progress.size} active · #{activity_day.up_next.size} next".freeze,
          description: "Progress against today's explicit workout and habit plan.".freeze,
          tone: :neutral
        ),
        Fact.new(
          key: :attention,
          title: "Plan status".freeze,
          value: (attention_reasons.empty? ? "No exceptions" : "#{attention_reasons.size} #{'item'.pluralize(attention_reasons.size)} to review").freeze,
          description: (attention_reasons.empty? ? "Nothing in today's records needs attention." : attention_reasons.to_sentence.capitalize.concat(".")).freeze,
          tone: attention_reasons.empty? ? :clear : :attention
        )
      ].freeze

      Summary.new(facts: facts)
    end

    def meal_summary_description(meals)
      return "No meals logged yet; nutrition completeness is not assessed." if meals.empty?

      case nutrition_summary.status
      when "complete" then "Known nutrition details are complete."
      when "estimated" then "Known nutrition details include estimates."
      when "incomplete" then "Some logged meal nutrition details are incomplete."
      else "Logged meals do not have nutrition details yet."
      end
    end
end
