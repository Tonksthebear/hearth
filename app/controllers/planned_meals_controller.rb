class PlannedMealsController < ApplicationController
  def create
    attributes = planned_meal_params
    planned_meal = PlannedMeal.build_for(
      household: Current.household,
      planned_on: attributes[:planned_on],
      recipe_id: attributes[:recipe_id],
      person_id: attributes[:person_id]
    )

    if planned_meal.save
      redirect_to meal_week_path(date: week_for(planned_meal.planned_on)),
        notice: "#{planned_meal.recipe.title} was added to the plan.",
        status: :see_other
    else
      @meal_week = meal_week(planned_meal: planned_meal)
      prepare_options
      render "meal_weeks/show", status: :unprocessable_entity
    end
  end

  def destroy
    planned_meal = Current.household.planned_meals.find(params[:id])
    planned_meal.destroy!

    redirect_to meal_week_path(date: week_for(params[:date])),
      notice: "#{planned_meal.recipe.title} was removed from the plan.",
      status: :see_other
  end

  private
    def planned_meal_params
      params.expect(planned_meal: %i[ planned_on recipe_id person_id ])
    end

    def meal_week(planned_meal: nil)
      MealWeek.for(
        household: Current.household,
        person: Current.person,
        date: params[:date],
        planned_meal: planned_meal
      )
    end

    def week_for(date)
      MealWeek.for(
        household: Current.household,
        person: Current.person,
        date: date
      ).to_param
    end

    def prepare_options
      recipe_choices = @meal_week.recipes.map { |recipe| [ recipe.title, recipe.id ] }
      @recipe_options = [ [ "Choose a recipe", "" ] ] + recipe_choices
      @optional_recipe_options = [ [ "No catalog recipe", "" ] ] + recipe_choices
      @person_options = [ [ "Whole household", "" ] ] +
        @meal_week.people.map { |person| [ person.name, person.id ] }
    end
end
