class Agent::SetupRequest::CancellationsController < ApplicationController
  def create
    request = Current.household.agent_setup_requests.find(params.expect(:setup_request_id))
    request.request_cancel!
    redirect_to agent_profiles_path(anchor: "agent_provider_#{request.certified_key}"),
      notice: "Setup request cancelled.", status: :see_other
  end
end
