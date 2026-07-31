class HouseholdWeeksController < ApplicationController
  def show
    @household_week = HouseholdWeek.for(
      household: Current.household,
      person: Current.person,
      date: params[:date]
    )
  end
end
