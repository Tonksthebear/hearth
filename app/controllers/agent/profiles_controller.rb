class Agent::ProfilesController < ApplicationController
  def index
    @providers = Agent::Profile::Certified.all.map { |candidate| candidate.state_for(Current.household) }
  end
end
