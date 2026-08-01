class MealWeek
  attr_reader :household, :person, :start_date, :planned_meal

  class << self
    def current(household:, person:, **)
      new(household: household, person: person, date: Date.current, **)
    end

    def for(household:, person:, date:, **)
      parsed_date = Date.iso8601(date.to_s)
      new(household: household, person: person, date: parsed_date, **)
    rescue ArgumentError, Date::Error
      current(household: household, person: person, **)
    end
  end

  def initialize(household:, person:, date:, planned_meal: nil)
    @household = household
    @person = person
    @start_date = date.beginning_of_week(:monday)
    @planned_meal = planned_meal || household.planned_meals.build(planned_on: date)
  end

  def end_date
    start_date + 6.days
  end

  def date_range
    start_date..end_date
  end

  def days
    date_range.to_a
  end

  def planned_meals
    @planned_meals ||= household.planned_meals
      .during(date_range)
      .visible_to(person)
      .includes(:person, :recipe, :meals)
      .order(:planned_on, :created_at)
  end

  def meals
    @meals ||= person.meals
      .during(date_range)
      .includes(meal_items: [ :recipe, :ingredient ])
      .order(:eaten_on, :created_at)
  end

  def planned_meals_for(day)
    planned_meals_by_date[day] || []
  end

  def meals_for(day)
    meals_by_date[day] || []
  end

  def converted_meal_for(planned_meal)
    converted_meals_by_plan_id[planned_meal.id]
  end

  def logging_date
    Date.current.in?(date_range) ? Date.current : start_date
  end

  def recipes
    @recipes ||= household.recipes.order(:title)
  end

  def people
    @people ||= household.people.order(:name)
  end

  def previous_date
    start_date - 7.days
  end

  def next_date
    start_date + 7.days
  end

  def to_param
    start_date.iso8601
  end

  private
    def planned_meals_by_date
      @planned_meals_by_date ||= planned_meals.group_by(&:planned_on)
    end

    def meals_by_date
      @meals_by_date ||= meals.group_by(&:eaten_on)
    end

    def converted_meals_by_plan_id
      @converted_meals_by_plan_id ||= person.meals
        .where(planned_meal_id: planned_meals.map(&:id))
        .index_by(&:planned_meal_id)
    end
end
