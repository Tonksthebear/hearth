class ShoppingListItem::PantryConfirmationsController < ApplicationController
  before_action :set_shopping_list_item
  before_action :set_pantry_item

  def new
    @purchase = { quantity: @shopping_list_item.quantity, unit: @shopping_list_item.unit }
  end

  def create
    @purchase = pantry_confirmation_params
    @pantry_item.record_purchase!(
      quantity: @purchase[:quantity],
      unit: @purchase[:unit],
      confirmed_by: Current.person
    )
    redirect_to shopping_list_path(date: @shopping_list_item.shopping_list.week_start),
      notice: "Pantry evidence recorded for #{@shopping_list_item.name}.",
      status: :see_other
  rescue ActiveRecord::RecordInvalid
    render :new, status: :unprocessable_entity
  end

  private
    def set_shopping_list_item
      @shopping_list_item = Current.household.shopping_list_items.find(params[:item_id])
      raise ActiveRecord::RecordNotFound unless @shopping_list_item.confirmable_into_pantry?
    end

    def set_pantry_item
      @pantry_item = PantryItem.for(household: Current.household, ingredient: @shopping_list_item.ingredient)
    end

    def pantry_confirmation_params
      params.expect(pantry_confirmation: %i[ quantity unit ])
    end
end
