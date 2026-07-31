module Agent::Contextual
  extend ActiveSupport::Concern

  CONTEXT_COLUMNS = %w[ household_id person_id conversation_id agent_session_id ].freeze

  included do
    validate :person_matches_household
    validate :conversation_matches_context
    validate :agent_session_matches_context
    validate :context_is_immutable, on: :update
  end

  private
    def person_matches_household
      return unless respond_to?(:person_id) && household_id
      if respond_to?(:person) && person
        return if person.household == household

        errors.add(:person, "must belong to this household")
        return
      end
      return unless person_id
      return if Person.where(id: person_id, household_id: household_id).exists?

      errors.add(:person, "must belong to this household")
    end

    def conversation_matches_context
      return unless respond_to?(:conversation_id) && conversation_id
      return if Agent::Conversation.where(id: conversation_id, household_id: household_id, person_id: person_id).exists?

      errors.add(:conversation, "must match this household and person")
    end

    def agent_session_matches_context
      return unless respond_to?(:agent_session_id) && agent_session_id
      return if Agent::Session.where(
        id: agent_session_id,
        household_id: household_id,
        person_id: person_id,
        conversation_id: conversation_id
      ).exists?

      errors.add(:agent_session, "must match this conversation context")
    end

    def context_is_immutable
      changed_context = CONTEXT_COLUMNS.select do |column|
        respond_to?("will_save_change_to_#{column}?") && public_send("will_save_change_to_#{column}?")
      end
      errors.add(:base, "Agent context cannot be changed") if changed_context.any?
    end
end
