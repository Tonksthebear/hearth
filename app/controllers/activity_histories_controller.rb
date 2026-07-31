class ActivityHistoriesController < ApplicationController
  def show
    @activity_history = ActivityHistory.new(household: Current.household, person: Current.person)
  end
end
