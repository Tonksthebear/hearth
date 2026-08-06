class PlannedMealIngredient::SubstitutionsController < ApplicationController
  before_action :set_requirement
  before_action :prepare_ingredient_name_options

  def new
    @substitution = {
      name: @requirement.replacement_display_name,
      quantity: @requirement.replacement_display_quantity || @requirement.display_quantity,
      unit: @requirement.replacement_unit || @requirement.unit
    }
  end

  def create
    @substitution = substitution_params
    name = @substitution[:name].to_s.squish

    if name.blank?
      @requirement.errors.add(:replacement_display_name, "must describe the replacement")
      render :new, status: :unprocessable_entity
    else
      @requirement.substitute!(
        ingredient: Ingredient.resolve!(household: Current.household, name: name),
        display_quantity: @substitution[:quantity],
        unit: @substitution[:unit],
        display_name: name
      )
      redirect_to planned_meal_ingredient_review_path(@requirement.planned_meal),
        notice: "#{@requirement.display_name} is now substituted with #{name}.",
        status: :see_other
    end
  rescue ActiveRecord::RecordInvalid
    render :new, status: :unprocessable_entity
  end

  private
    def set_requirement
      @requirement = PlannedMealIngredient.reviewable_by(Current.household, Current.person).find(params[:planned_meal_ingredient_id])
      @planned_meal = @requirement.planned_meal
      raise ActiveRecord::RecordNotFound unless @planned_meal.ingredient_review_open?
    end

    # Existing household ingredients are offered by name, and the autocomplete
    # still accepts a new one, because a substitution is exactly where a household
    # names something it has never cooked with before.
    def prepare_ingredient_name_options
      @ingredient_name_options = Current.household.ingredients.order(:name).pluck(:name, :name)
    end

    def substitution_params
      params.expect(substitution: %i[ name quantity unit ])
    end
end
