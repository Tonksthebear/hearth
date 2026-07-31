class PersonContextsController < ApplicationController
  def update
    person = Current.household.people.find(params.expect(:person_id))
    session[:person_id] = person.id

    redirect_to destination_path, status: :see_other
  end

  private
    def destination_path
      {
        "meals" => meal_week_path,
        "activities" => activity_week_path
      }.fetch(params[:destination].to_s, root_path)
    end
end
