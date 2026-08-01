class Agent::Turn::CancellationsController < ApplicationController
  def create
    conversation = scoped_conversations.find(params.expect(:conversation_id))
    turn = conversation.turns.where(browser_session: Current.session).find(params.expect(:turn_id))
    turn.request_cancel!
    redirect_to agent_conversation_path(conversation), notice: "Cancellation requested.", status: :see_other
  end

  private
    def scoped_conversations
      Current.person.agent_conversations.where(household: Current.household)
    end
end
