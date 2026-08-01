class Agent::TurnsController < ApplicationController
  def create
    conversation = scoped_conversations.find(params.expect(:conversation_id))
    raise ActiveRecord::RecordNotFound unless conversation.accepts_turns?

    conversation.enqueue_turn!(
      body: turn_params[:body],
      browser_session: Current.session,
      idempotency_key: turn_params[:idempotency_key]
    )
    redirect_to agent_conversation_path(conversation, anchor: "agent_turn_status"), status: :see_other
  rescue ActiveRecord::RecordInvalid => error
    redirect_to agent_conversation_path(conversation), alert: error.record.errors.full_messages.to_sentence, status: :see_other
  end

  private
    def scoped_conversations
      Current.person.agent_conversations.where(household: Current.household)
    end

    def turn_params
      params.expect(turn: %i[ body idempotency_key ])
    end
end
