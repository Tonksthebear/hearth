class ShoppingListsController < ApplicationController
  def show
    @meal_week = MealWeek.for(
      household: Current.household,
      person: Current.person,
      date: params[:date]
    )
    @shopping_list = ShoppingList.new(
      household: Current.household,
      date: @meal_week.start_date
    )
  end
end
