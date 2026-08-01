class Agent::ConversationsController < ApplicationController
  def index
    @conversations = scoped_conversations.includes(:profile, :messages).order(updated_at: :desc)
    @profiles = scoped_profiles.order(:name)
  end

  def new
    @profiles = scoped_profiles.includes(:installations).order(:name)
    @conversation = scoped_conversations.new
  end

  def create
    profile = scoped_profiles.find(conversation_params[:profile_id])
    @conversation = scoped_conversations.new(
      profile: profile,
      title: conversation_params[:title].presence || "New conversation"
    )
    if @conversation.save
      redirect_to agent_conversation_path(@conversation), status: :see_other
    else
      @profiles = scoped_profiles.includes(:installations).order(:name)
      render :new, status: :unprocessable_entity
    end
  end

  def show
    @conversation = scoped_conversations.includes(:profile).find(params[:id])
    @messages = @conversation.messages.order(:created_at, :id)
    @activities = @conversation.tool_activities.order(:created_at, :id)
    @citations = @conversation.citations.order(:created_at, :id)
    @plan = @conversation.plan
    @turn = @conversation.turns.order(created_at: :desc).first
    @turn_idempotency_key = SecureRandom.uuid
  end

  private
    def scoped_conversations
      Current.person.agent_conversations.where(household: Current.household, profile: scoped_profiles)
    end

    def scoped_profiles
      Current.household.agent_profiles.where(enabled: true)
    end

    def conversation_params
      params.expect(agent_conversation: %i[ profile_id title ])
    end
end
