class ActivityHistoriesController < ApplicationController
  def show
    @activity_history = ActivityHistory.new(
      household: Current.household,
      person: Current.person,
      before: params[:before]
    )
  end
end
