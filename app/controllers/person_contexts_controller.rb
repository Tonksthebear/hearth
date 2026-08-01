class PersonContextsController < ApplicationController
  def update
    person = Current.household.people.find(params.expect(:person_id))
    if person != Current.person
      Current.session.agent_operational_authorizations.where(revoked_at: nil).find_each do |authorization|
        authorization.revoke!(reason: "selected person changed", by: Current.user)
      end
    end
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
