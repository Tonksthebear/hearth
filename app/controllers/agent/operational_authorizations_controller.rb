class Agent::OperationalAuthorizationsController < ApplicationController
  def create
    agent_session = scoped_agent_sessions.find(params.expect(:agent_session_id))
    Agent::OperationalAuthorization.authorize!(
      agent_session: agent_session,
      reason: params.expect(:reason)
    )
    redirect_back fallback_location: root_path, notice: "Agent operational access enabled.", status: :see_other
  end

  def destroy
    authorization = Current.session.agent_operational_authorizations
      .where(household: Current.household, person: Current.person)
      .find(params[:id])
    authorization.revoke!(reason: "disabled by user", by: Current.user)
    redirect_back fallback_location: root_path, notice: "Agent operational access disabled.", status: :see_other
  end

  private
    def scoped_agent_sessions
      Agent::Session.joins(:conversation).where(
        browser_session: Current.session,
        household: Current.household,
        person: Current.person,
        status: %w[starting connected],
        agent_conversations: { status: "active" }
      )
    end
end
