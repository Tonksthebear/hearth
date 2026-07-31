class ActivityOverviewsController < ApplicationController
  def show
    @activity_overview = ActivityOverview.current(
      household: Current.household,
      person: Current.person
    )
  end
end
