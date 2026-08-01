class ShoppingListItem::CompletionsController < ApplicationController
  before_action :set_shopping_list_item

  def create
    @shopping_list_item.complete!
    redirect_to shopping_list_path(date: @shopping_list_item.shopping_list.week_start), status: :see_other
  end

  def destroy
    @shopping_list_item.uncomplete!
    redirect_to shopping_list_path(date: @shopping_list_item.shopping_list.week_start), status: :see_other
  end

  private
    def set_shopping_list_item
      @shopping_list_item = Current.household.shopping_list_items.find(params[:item_id])
    end
end
