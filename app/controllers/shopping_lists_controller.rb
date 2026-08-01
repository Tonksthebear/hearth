class ShoppingListsController < ApplicationController
  def show
    return head :no_content if request.headers["X-Sec-Purpose"].to_s.split.include?("prefetch")

    @meal_week = MealWeek.for(
      household: Current.household,
      person: Current.person,
      date: params[:date]
    )
    @shopping_list = ShoppingList.for(
      household: Current.household,
      date: @meal_week.start_date
    )
    @shopping_list_items = @shopping_list.display_items
    @shopping_list_item = @shopping_list.items.build
  end
end
