class IngredientsController < ApplicationController
  before_action :set_ingredient, only: %i[ edit update ]

  def index
    @ingredients = Current.household.ingredients
      .includes(ingredient_nutrient_values: :nutrient)
      .order(:name)
    @nutrients = Nutrient.displayed
  end

  def edit
    prepare_nutrient_rows
  end

  def update
    @ingredient.assign_attributes(ingredient_params)
    if @ingredient.save
      redirect_to ingredients_path, notice: "Nutrition for #{@ingredient.name} was updated.", status: :see_other
    else
      prepare_nutrient_rows
      render :edit, status: :unprocessable_entity
    end
  end

  private
    def set_ingredient
      @ingredient = Current.household.ingredients
        .includes(ingredient_nutrient_values: :nutrient)
        .find(params[:id])
    end

    def prepare_nutrient_rows
      @nutrients = Nutrient.displayed
      existing = @ingredient.ingredient_nutrient_values.index_by(&:nutrient_id)
      @nutrients.each { |nutrient| @ingredient.ingredient_nutrient_values.build(nutrient:) unless existing[nutrient.id] }
      @ingredient.nutrition_provenance_status ||= "personal"
    end

    def ingredient_params
      permitted = params.fetch(:ingredient).permit(
        :nutrition_source_name,
        :nutrition_provenance_status,
        :food_data_central_id,
        ingredient_nutrient_values_attributes: %i[ id nutrient_id amount_per_100_grams _destroy ]
      )
      permitted.fetch(:ingredient_nutrient_values_attributes, {}).each_value do |attributes|
        attributes[:_destroy] = "1" if attributes[:id].present? && attributes[:amount_per_100_grams].blank?
      end
      permitted
    end
end
