class Agent::SetupRequestsController < ApplicationController
  def create
    request = Agent::SetupRequest.enqueue!(
      household: Current.household,
      requested_by: Current.user,
      certified_key: setup_request_params[:certified_key],
      action: setup_request_params[:action],
      authentication_method_id: setup_request_params[:authentication_method_id],
      idempotency_key: setup_request_params[:idempotency_key].presence || SecureRandom.uuid
    )
    redirect_to agent_profiles_path(anchor: "agent_provider_#{request.certified_key}"),
      notice: "Agent setup request queued.", status: :see_other
  rescue ActiveRecord::RecordInvalid, ArgumentError => error
    redirect_to agent_profiles_path, alert: error.message, status: :see_other
  end

  private
    def setup_request_params
      params.expect(setup_request: %i[ certified_key action authentication_method_id idempotency_key ])
    end
end
