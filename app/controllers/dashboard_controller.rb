class DashboardController < ApplicationController
  def show
    @person = Current.user.person
    @household = @person.household
  end
end
