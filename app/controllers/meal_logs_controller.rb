class MealLogsController < ApplicationController
  def create
    attributes = meal_log_params
    meal_log = MealLog.build_for(
      household: Current.household,
      person: Current.person,
      eaten_on: attributes[:eaten_on],
      recipe_id: attributes[:recipe_id],
      ad_hoc_description: attributes[:ad_hoc_description]
    )

    if meal_log.save
      redirect_to meal_week_path(date: week_for(meal_log.eaten_on)),
        notice: "#{meal_log.description} was logged for #{Current.person.name}.",
        status: :see_other
    else
      @meal_week = meal_week(meal_log: meal_log)
      prepare_options
      render "meal_weeks/show", status: :unprocessable_entity
    end
  end

  def destroy
    meal_log = Current.person.meal_logs.find(params[:id])
    meal_log.destroy!

    redirect_to meal_week_path(date: week_for(params[:date])),
      notice: "#{meal_log.description} was removed from #{Current.person.name}'s log.",
      status: :see_other
  end

  private
    def meal_log_params
      params.expect(meal_log: %i[ eaten_on recipe_id ad_hoc_description ])
    end

    def meal_week(meal_log: nil)
      MealWeek.for(
        household: Current.household,
        person: Current.person,
        date: params[:date],
        meal_log: meal_log
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
