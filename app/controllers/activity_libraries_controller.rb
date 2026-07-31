class ActivityLibrariesController < ApplicationController
  def show
    @activity_library = ActivityLibrary.new(household: Current.household, person: Current.person)
  end
end
