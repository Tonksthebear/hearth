class DashboardController < ApplicationController
  def show
    @person = Current.person
    @household = Current.household
  end
end
