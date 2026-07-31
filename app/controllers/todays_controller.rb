class TodaysController < ApplicationController
  def show
    @today = Person::Today.current(household: Current.household, person: Current.person)
  end
end
