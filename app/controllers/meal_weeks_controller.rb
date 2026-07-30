class MealWeeksController < ApplicationController
  def show
    @meal_week = MealWeek.for(
      household: Current.household,
      person: Current.person,
      date: params[:date]
    )
    prepare_options
  end

  private
    def prepare_options
      recipe_choices = @meal_week.recipes.map { |recipe| [ recipe.title, recipe.id ] }
      @recipe_options = [ [ "Choose a recipe", "" ] ] + recipe_choices
      @optional_recipe_options = [ [ "No catalog recipe", "" ] ] + recipe_choices
      @person_options = [ [ "Whole household", "" ] ] +
        @meal_week.people.map { |person| [ person.name, person.id ] }
    end
end
