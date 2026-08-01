class RecipesController < ApplicationController
  before_action :set_recipe, only: %i[ show edit update ]
  before_action :prepare_form, only: %i[ index new create edit update ]

  def index
    @query = params[:q].to_s
    @status = params[:status].to_s
    @recipes = Current.household.recipes
      .matching(@query)
      .with_provenance_status(@status)
      .with_attached_cover
      .order(:title)
  end

  def show
    @recipe_feedbacks = @recipe.feedback_history
  end

  def new
    @recipe = Current.household.recipes.build(provenance_status: :personal)
    @recipe.add_ingredient
    @recipe.add_instruction
    prepare_nutrition_rows
    prepare_ingredient_reference_options
  end

  def create
    attributes = recipe_attributes
    @recipe = Current.household.recipes.build(attributes)
    @recipe.cover_uploaded_this_request = attributes[:cover].is_a?(ActionDispatch::Http::UploadedFile)
    @recipe.normalize_positions
    prepare_ingredient_reference_options

    if structural_action?
      @recipe.preserve_cover_for_form
      @recipe.ensure_form_rows
      prepare_nutrition_rows
      render_form_update
    elsif @recipe.save
      redirect_to @recipe, notice: "#{@recipe.title} was created.", status: :see_other
    else
      @recipe.preserve_cover_for_form
      prepare_nutrition_rows
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    prepare_nutrition_rows
    prepare_ingredient_reference_options
  end

  def update
    attributes = recipe_attributes
    @recipe.assign_attributes(attributes)
    @recipe.cover_uploaded_this_request = attributes[:cover].is_a?(ActionDispatch::Http::UploadedFile)
    @recipe.normalize_positions
    prepare_ingredient_reference_options

    if structural_action?
      @recipe.preserve_cover_for_form
      @recipe.ensure_form_rows
      prepare_nutrition_rows
      render_form_update
    elsif @recipe.save
      redirect_to @recipe, notice: "#{@recipe.title} was updated.", status: :see_other
    else
      @recipe.preserve_cover_for_form
      prepare_nutrition_rows
      render :edit, status: :unprocessable_entity
    end
  end

  private
    def set_recipe
      scope = Current.household.recipes
      if action_name == "show"
        scope = scope.includes(
          :recipe_nutrient_values,
          recipe_instructions: :referenced_recipe_ingredients,
          recipe_ingredients: { ingredient: { ingredient_nutrient_values: :nutrient } }
        )
      end
      @recipe = scope.find(params[:id])
    end

    def prepare_form
      @provenance_statuses = Recipe.provenance_statuses.keys
      @nutrients = Nutrient.displayed
    end

    def prepare_nutrition_rows
      existing = @recipe.recipe_nutrient_values.index_by(&:nutrient_id)
      @nutrients.each { |nutrient| @recipe.recipe_nutrient_values.build(nutrient:) unless existing[nutrient.id] }
    end

    def prepare_ingredient_reference_options
      @ingredient_name_options = [ [ "", "" ], *Current.household.ingredients.order(:name).pluck(:name, :name) ]
      current_names = @recipe.recipe_ingredients
        .reject(&:marked_for_destruction?)
        .filter_map { |ingredient| ingredient.display_name.presence }
        .map { |name| [ name, name ] }
      @ingredient_name_options = [ *@ingredient_name_options, *current_names ].uniq { |_, value| value }
      @ingredient_reference_options = helpers.elements_options_for_select(
        @recipe.ingredient_reference_options,
        disabled: @recipe.disabled_ingredient_reference_keys
      )
    end

    def recipe_params
      permitted = params.fetch(:recipe).permit(
        :title,
        :description,
        :cover,
        :remove_cover,
        :yield,
        :serving_count,
        :source_name,
        :source_url,
        :provenance_status,
        recipe_ingredients_attributes: %i[ id display_quantity unit display_name gram_weight notes form_key _destroy ],
        recipe_nutrient_values_attributes: %i[ id nutrient_id amount _destroy ],
        recipe_instructions_attributes: [
          :id,
          :body,
          :duration_amount,
          :duration_unit,
          :temperature_amount,
          :temperature_unit,
          :_destroy,
          { ingredient_reference_keys: [] }
        ]
      )
      permitted.fetch(:recipe_nutrient_values_attributes, {}).each_value do |attributes|
        attributes[:_destroy] = "1" if attributes[:id].present? && attributes[:amount].blank?
      end
      permitted
    end

    def recipe_attributes
      recipe_params.tap do |attributes|
        cover = attributes[:cover]
        next unless cover.is_a?(String) && cover.present?
        next if ActiveStorage::Blob.find_signed(cover)

        attributes.delete(:cover)
        attributes[:cover_reference_invalid] = true
      end
    end

    def structural_action?
      if params[:add_ingredient]
        @recipe.add_ingredient
      elsif params[:add_instruction]
        @recipe.add_instruction
      elsif params[:remove_ingredient]
        @recipe.remove_ingredient(params[:remove_ingredient])
      elsif params[:remove_instruction]
        @recipe.remove_instruction(params[:remove_instruction])
      end
    end

    def render_form_update
      prepare_ingredient_reference_options
      render turbo_stream: turbo_stream.replace(
        "recipe_form",
        partial: "recipes/form",
        locals: {
          recipe: @recipe,
          provenance_statuses: @provenance_statuses,
          ingredient_name_options: @ingredient_name_options,
          ingredient_reference_options: @ingredient_reference_options,
          nutrients: @nutrients
        }
      )
    end
end
