class PersonContextsController < ApplicationController
  def update
    person = Current.household.people.find(params.expect(:person_id))
    session[:person_id] = person.id

    redirect_to root_path, status: :see_other
  end
end
