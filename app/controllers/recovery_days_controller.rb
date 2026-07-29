class RecoveryDaysController < ApplicationController
  def show
    @recovery_day = RecoveryDay.current(household: Current.household, person: Current.person)
  end
end
