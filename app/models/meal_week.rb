class MealWeek
  attr_reader :household, :person, :start_date, :planned_meal, :meal_log

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

  def initialize(household:, person:, date:, planned_meal: nil, meal_log: nil)
    @household = household
    @person = person
    @start_date = date.beginning_of_week(:monday)
    @planned_meal = planned_meal || household.planned_meals.build(planned_on: date)
    @meal_log = meal_log || person.meal_logs.build(household: household, eaten_on: date)
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
      .includes(:person, :recipe)
      .order(:planned_on, :created_at)
  end

  def meal_logs
    @meal_logs ||= person.meal_logs
      .during(date_range)
      .includes(:recipe)
      .order(:eaten_on, :created_at)
  end

  def planned_meals_for(day)
    planned_meals_by_date[day] || []
  end

  def meal_logs_for(day)
    meal_logs_by_date[day] || []
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

    def meal_logs_by_date
      @meal_logs_by_date ||= meal_logs.group_by(&:eaten_on)
    end
end
