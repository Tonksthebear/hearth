class RecipesController < ApplicationController
  before_action :set_recipe, only: %i[ show edit update ]
  before_action :prepare_form, only: %i[ index new create edit update ]

  def index
    @query = params[:q].to_s
    @status = params[:status].to_s
    @recipes = Current.household.recipes
      .matching(@query)
      .with_provenance_status(@status)
      .order(:title)
  end

  def show
  end

  def new
    @recipe = Current.household.recipes.build(provenance_status: :personal)
    @recipe.add_ingredient
    @recipe.add_instruction
  end

  def create
    @recipe = Current.household.recipes.build(recipe_params)
    @recipe.normalize_positions

    if structural_action?
      @recipe.ensure_form_rows
      render_form_update
    elsif @recipe.save
      redirect_to @recipe, notice: "#{@recipe.title} was created.", status: :see_other
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    @recipe.assign_attributes(recipe_params)
    @recipe.normalize_positions

    if structural_action?
      @recipe.ensure_form_rows
      render_form_update
    elsif @recipe.save
      redirect_to @recipe, notice: "#{@recipe.title} was updated.", status: :see_other
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private
    def set_recipe
      @recipe = Current.household.recipes.find(params[:id])
    end

    def prepare_form
      @provenance_statuses = Recipe.provenance_statuses.keys
    end

    def recipe_params
      params.fetch(:recipe).permit(
        :title,
        :description,
        :yield,
        :source_name,
        :source_url,
        :provenance_status,
        recipe_ingredients_attributes: %i[ id amount unit name notes _destroy ],
        recipe_instructions_attributes: %i[ id body _destroy ]
      )
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
      render turbo_stream: turbo_stream.replace(
        "recipe_form",
        partial: "recipes/form",
        locals: { recipe: @recipe, provenance_statuses: @provenance_statuses }
      )
    end
end
