class MealsController < ApplicationController
  before_action :set_visible_meal, only: :show
  before_action :set_owned_meal, only: %i[ edit update destroy ]
  before_action :prepare_options, only: %i[ new create edit update ]

  def new
    @meal = Meal.build_for(
      household: Current.household,
      person: Current.person,
      attributes: { eaten_on: requested_date }
    )
    @meal.add_item(:free_text)
  end

  def create
    @meal = Meal.build_for(
      household: Current.household,
      person: Current.person,
      attributes: meal_params
    )
    @meal.normalize_positions

    if structural_action?
      @meal.ensure_form_item
      prepare_feedback_rows
      render_form_update
    elsif @meal.save
      redirect_to @meal, notice: "#{@meal.description} was logged for #{Current.person.name}.", status: :see_other
    else
      @meal.ensure_form_item
      prepare_feedback_rows
      render :new, status: :unprocessable_entity
    end
  end

  def show
  end

  def edit
    prepare_feedback_rows
  end

  def update
    @meal.assign_attributes(meal_params)
    @meal.normalize_positions

    if structural_action?
      @meal.ensure_form_item
      prepare_feedback_rows
      render_form_update
    elsif @meal.save
      redirect_to @meal, notice: "#{@meal.description} was updated.", status: :see_other
    else
      @meal.ensure_form_item
      prepare_feedback_rows
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    description = @meal.description
    date = @meal.eaten_on
    @meal.destroy!

    redirect_to meal_week_path(date: MealWeek.for(
      household: Current.household,
      person: Current.person,
      date: date
    )), notice: "#{description} was removed from #{Current.person.name}'s meals.", status: :see_other
  end

  private
    def set_visible_meal
      @meal = Current.household.meals
        .includes(meal_items: [ :recipe, :ingredient, :recipe_feedback, :meal_item_nutrient_values ])
        .find(params[:id])
    end

    def set_owned_meal
      @meal = Current.person.meals
        .includes(meal_items: [ :recipe, :ingredient, :recipe_feedback, :meal_item_nutrient_values ])
        .find(params[:id])
    end

    def meal_params
      params.fetch(:meal).permit(
        :eaten_on,
        :eaten_at,
        :notes,
        meal_items_attributes: [
          :id,
          :source_kind,
          :recipe_id,
          :ingredient_id,
          :snapshot_label,
          :portion_amount,
          :portion_unit,
          :substitutions,
          :notes,
          :_destroy,
          { recipe_feedback_attributes: %i[ id body _destroy ] }
        ]
      )
    end

    def structural_action?
      if params[:add_recipe_item]
        @meal.add_item(:recipe)
      elsif params[:add_ingredient_item]
        @meal.add_item(:ingredient)
      elsif params[:add_free_text_item]
        @meal.add_item(:free_text)
      elsif params[:remove_item]
        @meal.remove_item(params[:remove_item])
      end
    end

    def prepare_options
      @recipe_options = [ [ "Choose a recipe", "" ], *Current.household.recipes.order(:title).pluck(:title, :id) ]
      @ingredient_options = [ [ "Choose an ingredient", "" ], *Current.household.ingredients.order(:name).pluck(:name, :id) ]
    end

    def prepare_feedback_rows
      @meal.meal_items.each do |item|
        item.build_recipe_feedback if item.recipe? && !item.recipe_feedback
      end
    end

    def render_form_update
      render turbo_stream: turbo_stream.replace(
        "meal_form",
        partial: "meals/form",
        locals: { meal: @meal, recipe_options: @recipe_options, ingredient_options: @ingredient_options }
      )
    end

    def requested_date
      Date.iso8601(params[:date].to_s)
    rescue Date::Error
      Date.current
    end
end
