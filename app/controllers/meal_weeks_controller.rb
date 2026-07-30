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
      @recipe_options = @meal_week.recipes.map { |recipe| [ recipe.title, recipe.id ] }
      @optional_recipe_options = [ [ "No catalog recipe", "" ] ] + @recipe_options
      @person_options = [ [ "Whole household", "" ] ] +
        @meal_week.people.map { |person| [ person.name, person.id ] }
    end
end
