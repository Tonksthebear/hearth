class Agent::MutationExecution < ApplicationRecord
  belongs_to :mutation_proposal, class_name: "Agent::MutationProposal"
  belongs_to :executed_by, class_name: "User", optional: true

  validates :operation, :idempotency_key, :input_digest, :executed_at, presence: true
  validates :outcome, inclusion: { in: %w[ succeeded failed ] }

  delegate :household, :person, :conversation, :agent_session, to: :mutation_proposal
end
