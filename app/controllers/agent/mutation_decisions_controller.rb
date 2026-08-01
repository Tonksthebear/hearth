class Agent::MutationDecisionsController < ApplicationController
  def create
    proposal = scoped_proposals.find(params.expect(:mutation_proposal_id))
    proposal.decide!(
      outcome: params.expect(:outcome),
      by: Current.user,
      token: params.expect(:confirmation_token),
      reason: params[:reason]
    )
    render_center(proposal)
  rescue ActiveRecord::RecordInvalid, ActiveRecord::StaleObjectError => error
    redirect_back fallback_location: root_path, alert: error.message, status: :see_other
  end

  def destroy
    proposal = scoped_proposals.find(params.expect(:mutation_proposal_id))
    proposal.cancel!(reason: "cancelled by user", by: Current.user)
    render_center(proposal)
  end

  private
    def scoped_proposals
      Agent::MutationProposal.where(
        household: Current.household,
        person: Current.person,
        agent_session: Agent::Session.where(browser_session: Current.session)
      )
    end

    def render_center(proposal)
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            "agent_confirmation_center",
            partial: "agent/mutation_proposals/center",
            locals: { proposal: proposal, confirmation_token: nil }
          )
        end
        format.html { redirect_back fallback_location: root_path, status: :see_other }
      end
    end
end
