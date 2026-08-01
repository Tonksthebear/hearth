class ShoppingListItemsController < ApplicationController
  before_action :set_shopping_list_item, only: %i[ edit update ]
  before_action :set_removable_shopping_list_item, only: :destroy

  def create
    @shopping_list = Current.household.shopping_lists.find_by!(week_start: shopping_week_start)
    @shopping_list_item = @shopping_list.items.build

    if @shopping_list_item.apply_user_attributes(shopping_list_item_params)
      redirect_to shopping_list_path(date: @shopping_list.week_start), notice: "Item was added.", status: :see_other
    else
      prepare_show
      render "shopping_lists/show", status: :unprocessable_entity
    end
  end

  def edit
    @shopping_list = @shopping_list_item.shopping_list
  end

  def update
    if @shopping_list_item.apply_user_attributes(shopping_list_item_params)
      redirect_to shopping_list_path(date: @shopping_list_item.shopping_list.week_start), notice: "Item was updated.", status: :see_other
    else
      @shopping_list = @shopping_list_item.shopping_list
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    shopping_list = @shopping_list_item.shopping_list
    @shopping_list_item.destroy!
    redirect_to shopping_list_path(date: shopping_list.week_start), notice: "Item was removed.", status: :see_other
  end

  private
    def set_shopping_list_item
      @shopping_list_item = Current.household.shopping_list_items.find(params[:id])
    end

    def set_removable_shopping_list_item
      @shopping_list_item = Current.household.shopping_list_items.find(params[:id])
      raise ActiveRecord::RecordNotFound unless @shopping_list_item.removable_by_person?
    end

    def shopping_list_item_params
      params.expect(shopping_list_item: %i[ name quantity unit notes ])
    end

    def shopping_week_start
      raise ActiveRecord::RecordNotFound if params[:date].blank?

      ShoppingList.week_start_for(params[:date])
    rescue Date::Error
      raise ActiveRecord::RecordNotFound
    end

    def prepare_show
      @meal_week = MealWeek.for(
        household: Current.household,
        person: Current.person,
        date: @shopping_list.week_start
      )
      @shopping_list_items = @shopping_list.display_items
    end
end
