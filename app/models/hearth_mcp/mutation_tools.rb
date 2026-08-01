require "mcp"

module HearthMcp
  module MutationTools
    CAPABILITY = "health.write"
    ID = { type: "integer", minimum: 1 }.freeze
    TEXT = { type: [ "string", "null" ], maxLength: 10_000 }.freeze
    DATE = { type: "string", format: "date" }.freeze
    IDEMPOTENCY = { type: "string", minLength: 8, maxLength: 200 }.freeze
    RESULT_SCHEMA = {
      type: "object",
      properties: {
        status: { type: "string" },
        proposal_id: { type: [ "integer", "null" ] },
        deadline_at: { type: [ "string", "null" ] },
        next_action: { type: [ "string", "null" ] },
        result: { type: "object" }
      },
      required: %w[status proposal_id deadline_at next_action result],
      additionalProperties: false
    }.freeze
    FEEDBACK_SCHEMA = {
      type: "object",
      properties: { id: ID, body: TEXT, _destroy: { type: "boolean" } },
      additionalProperties: false
    }.freeze
    MEAL_ITEM_SCHEMA = {
      type: "object",
      properties: {
        id: ID,
        source_kind: { type: "string", enum: %w[recipe ingredient free_text] },
        recipe_id: ID,
        ingredient_id: ID,
        snapshot_label: { type: "string", maxLength: 500 },
        portion_amount: { type: [ "number", "null" ], exclusiveMinimum: 0 },
        portion_unit: { type: [ "string", "null" ], maxLength: 100 },
        substitutions: TEXT,
        notes: TEXT,
        _destroy: { type: "boolean" },
        recipe_feedback_attributes: FEEDBACK_SCHEMA
      },
      required: %w[source_kind],
      additionalProperties: false
    }.freeze
    MEASURE_SCHEMA = {
      type: "object",
      properties: {
        id: ID, habit_metric_id: ID, number_value: { type: [ "number", "null" ] },
        duration_value: { type: [ "integer", "null" ], minimum: 0 },
        time_of_day_value: { type: [ "string", "null" ] },
        boolean_value: { type: [ "boolean", "null" ] }
      },
      required: %w[habit_metric_id],
      additionalProperties: false
    }.freeze
    TRAINING_SET_SCHEMA = {
      type: "object",
      properties: {
        id: ID, dose_class: { type: [ "string", "null" ], enum: [ "none", "strength", "zone2", "vigorous", nil ] },
        reps: { type: [ "integer", "null" ], minimum: 0 }, load_amount: { type: [ "number", "null" ], minimum: 0 },
        load_unit: { type: [ "string", "null" ] }, duration_seconds: { type: [ "integer", "null" ], minimum: 0 },
        rest_seconds: { type: [ "integer", "null" ], minimum: 0 }, distance_amount: { type: [ "number", "null" ], minimum: 0 },
        distance_unit: { type: [ "string", "null" ] }, count: { type: [ "integer", "null" ], minimum: 0 },
        count_unit: { type: [ "string", "null" ] }, average_heart_rate_bpm: { type: [ "integer", "null" ], minimum: 0 },
        peak_heart_rate_bpm: { type: [ "integer", "null" ], minimum: 0 }, rpe: { type: [ "number", "null" ] },
        rir: { type: [ "number", "null" ] }, completed: { type: "boolean" }, notes: TEXT, _destroy: { type: "boolean" }
      },
      additionalProperties: false
    }.freeze
    TRAINING_EXERCISE_SCHEMA = {
      type: "object",
      properties: {
        id: ID, exercise_id: ID, snapshot_name: { type: "string" }, snapshot_modality: { type: "string" },
        snapshot_movement_pattern: { type: "string" }, snapshot_equipment: TEXT, snapshot_guidance: TEXT,
        snapshot_performance_kind: { type: "string" }, snapshot_dose_class: { type: [ "string", "null" ] },
        snapshot_rep_min: { type: [ "integer", "null" ] }, snapshot_rep_max: { type: [ "integer", "null" ] },
        snapshot_work_seconds: { type: [ "integer", "null" ] }, snapshot_rest_seconds: { type: [ "integer", "null" ] },
        snapshot_target_distance_amount: { type: [ "number", "null" ] }, snapshot_target_distance_unit: { type: [ "string", "null" ] },
        snapshot_target_count: { type: [ "integer", "null" ] }, snapshot_target_count_unit: { type: [ "string", "null" ] },
        snapshot_per_side: { type: "boolean" }, snapshot_tempo_cue: TEXT,
        snapshot_target_heart_rate_min: { type: [ "integer", "null" ] }, snapshot_target_heart_rate_max: { type: [ "integer", "null" ] },
        snapshot_target_heart_rate_unit: { type: [ "string", "null" ] }, snapshot_target_rpe: { type: [ "number", "null" ] },
        snapshot_target_rir: { type: [ "number", "null" ] }, snapshot_load_guidance: TEXT,
        difficulty: TEXT, soreness_or_pain: TEXT, substitution: TEXT, next_time_adjustment: TEXT, notes: TEXT,
        _destroy: { type: "boolean" }, sets: { type: "array", minItems: 1, items: TRAINING_SET_SCHEMA }
      },
      required: %w[snapshot_name sets],
      additionalProperties: false
    }.freeze
    TRAINING_BLOCK_SCHEMA = {
      type: "object",
      properties: {
        id: ID, snapshot_title: { type: "string" }, snapshot_block_kind: { type: "string" },
        snapshot_dose_class: { type: "string" }, actual_duration_seconds: { type: [ "integer", "null" ], minimum: 0 },
        notes: TEXT, _destroy: { type: "boolean" }, exercises: { type: "array", minItems: 1, items: TRAINING_EXERCISE_SCHEMA }
      },
      required: %w[snapshot_title snapshot_block_kind snapshot_dose_class exercises],
      additionalProperties: false
    }.freeze

    class Base < MCP::Tool
      class << self
        def mutation_contract(name:, description:, properties:, required: [])
          tool_name name
          self.description "#{description} Consequential calls first stage a durable pending proposal; then request ACP permission with this operation and the same idempotency key."
          input_schema(
            type: "object",
            properties: properties.merge(idempotency_key: IDEMPOTENCY),
            required: (required + %w[idempotency_key]),
            additionalProperties: false
          )
          output_schema RESULT_SCHEMA
          annotations(read_only_hint: false, destructive_hint: name.start_with?("delete_"), idempotent_hint: true, open_world_hint: false)
        end

        def perform(operation, idempotency_key:, server_context:, **arguments)
          grant = server_context.fetch(:grant)
          return error("Operational write authorization is required") unless authorized?(grant)
          return error("Grant call limit exhausted") unless grant.consume(calls: 1) == 1

          context = grant
          Agent::Mutation::Operations.validate_arguments!(operation: operation, arguments: arguments)
          if (existing = grant.agent_session.mutation_proposals.find_by(idempotency_key: idempotency_key))
            unless existing.operation == operation && existing.input_digest == Agent::MutationProposal.input_digest_for(arguments)
              raise ArgumentError, "Idempotency key was reused with different input"
            end
            return response(proposal_payload(existing), grant)
          end
          expected = Agent::Mutation::Operations.expected_state(operation: operation, arguments: arguments, proposal: context)
          if Agent::Mutation::Operations.consequential?(operation: operation, arguments: arguments, context: context)
            authorization = grant.agent_session.active_operational_authorization
            deadline = [ grant.expires_at, authorization.expires_at, Acp::Connection::DEFAULT_TIMEOUT.seconds.from_now ].min
            proposal, token = Agent::MutationProposal.propose!(
              grant: grant,
              operation: operation,
              arguments: arguments,
              preview: Agent::Mutation::Operations.preview(operation: operation, arguments: arguments, context: context),
              expected_state: expected,
              idempotency_key: idempotency_key,
              deadline_at: deadline
            )
            proposal.broadcast_confirmation(token) if token
            payload = proposal_payload(proposal)
          else
            execution = Agent::MutationProposal.execute_immediate!(
              grant: grant, operation: operation, arguments: arguments,
              expected_state: expected, idempotency_key: idempotency_key
            )
            payload = { status: "executed", proposal_id: execution.mutation_proposal_id, deadline_at: nil, next_action: nil, result: execution.result }
          end
          response(payload, grant)
        rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotFound, ActiveRecord::DeleteRestrictionError,
          ActiveRecord::StaleObjectError, Agent::Mutation::Operations::Prohibited, ArgumentError => error
          error(error.message)
        end

        def response(payload, grant)
          json = JSON.generate(payload)
          tokens = (json.bytesize / 4.0).ceil
          return error("Response exceeds the remaining output budget") unless grant.consume(calls: 0, output_tokens: tokens) == 1
          MCP::Tool::Response.new([ { type: "text", text: json } ], structured_content: payload)
        end

        def proposal_payload(proposal)
          {
            status: proposal.status,
            proposal_id: proposal.id,
            deadline_at: proposal.permission_request&.deadline_at&.utc&.iso8601,
            next_action: proposal.status == "pending" ? "Request ACP permission for #{proposal.operation} with the same idempotency_key after staging this proposal." : nil,
            result: proposal.execution&.result || {}
          }
        end

        def error(message)
          MCP::Tool::Response.new([ { type: "text", text: JSON.generate(error: message) } ], error: true)
        end

        def authorized?(grant)
          grant.allows_capability?("health.write") && grant.agent_session.active_operational_authorization.present?
        end
      end
    end

    PLAN_PROPERTIES = { planned_on: DATE, recipe_id: ID }.freeze
    MEAL_PROPERTIES = {
      eaten_on: DATE, eaten_at: { type: [ "string", "null" ], format: "date-time" }, notes: TEXT,
      meal_items: { type: "array", minItems: 1, items: MEAL_ITEM_SCHEMA }
    }.freeze
    TRAINING_PROPERTIES = {
      snapshot_title: { type: "string", maxLength: 500 }, performed_on: DATE, notes: TEXT,
      blocks: { type: "array", minItems: 1, items: TRAINING_BLOCK_SCHEMA }
    }.freeze
    CHECK_IN_PROPERTIES = {
      person_habit_id: ID, checked_on: DATE, notes: TEXT,
      measurements: { type: "array", minItems: 1, items: MEASURE_SCHEMA }
    }.freeze

    DEFINITIONS = {
      "create_planned_meal" => [ "Plan one meal for the selected person.", PLAN_PROPERTIES, %w[planned_on recipe_id] ],
      "update_planned_meal" => [ "Update one selected-person meal plan.", PLAN_PROPERTIES.merge(id: ID), %w[id] ],
      "delete_planned_meal" => [ "Propose removing one unlinked meal plan.", { id: ID }, %w[id] ],
      "log_planned_meal" => [ "Log one explicit eligible planned meal.", { id: ID }, %w[id] ],
      "create_meal" => [ "Log one complete selected-person meal aggregate.", MEAL_PROPERTIES, %w[eaten_on meal_items] ],
      "update_meal" => [ "Update one complete selected-person meal aggregate.", MEAL_PROPERTIES.merge(id: ID), %w[id] ],
      "delete_meal" => [ "Propose unlogging one meal and its complete dependent graph.", { id: ID }, %w[id] ],
      "create_training_session" => [ "Create one in-progress training aggregate.", TRAINING_PROPERTIES, %w[snapshot_title performed_on blocks] ],
      "update_training_session" => [ "Update one training aggregate; completed sessions require confirmation.", TRAINING_PROPERTIES.merge(id: ID), %w[id] ],
      "complete_training_session" => [ "Complete one valid in-progress training aggregate.", { id: ID }, %w[id] ],
      "delete_training_session" => [ "Propose deleting one in-progress training aggregate.", { id: ID }, %w[id] ],
      "update_weekly_dose_targets" => [ "Propose changing selected-person weekly dose targets.", {
        weekly_strength_sessions_target: { type: [ "integer", "null" ], minimum: 1 },
        weekly_structured_minutes_target: { type: [ "integer", "null" ], minimum: 1 },
        weekly_zone2_minutes_target: { type: [ "integer", "null" ], minimum: 1 },
        weekly_vigorous_minutes_target: { type: [ "integer", "null" ], minimum: 1 }
      }, [] ],
      "upsert_person_habit" => [ "Propose assigning or configuring one selected-person habit.", {
        habit_id: ID, active: { type: "boolean" },
        sunday: { type: "boolean" }, monday: { type: "boolean" }, tuesday: { type: "boolean" },
        wednesday: { type: "boolean" }, thursday: { type: "boolean" }, friday: { type: "boolean" }, saturday: { type: "boolean" },
        person_habit_metrics_attributes: { type: "array", items: MEASURE_SCHEMA }
      }, %w[habit_id] ],
      "create_habit_check_in" => [ "Create one selected-person habit check-in aggregate.", CHECK_IN_PROPERTIES, %w[person_habit_id checked_on measurements] ],
      "update_habit_check_in" => [ "Update one selected-person habit check-in aggregate.", CHECK_IN_PROPERTIES.merge(id: ID), %w[id] ],
      "delete_habit_check_in" => [ "Propose deleting one selected-person habit check-in aggregate.", { id: ID }, %w[id] ]
    }.freeze

    ALL = DEFINITIONS.map do |name, (description, properties, required)|
      Class.new(Base) do
        mutation_contract name: name, description: description, properties: properties, required: required
        define_singleton_method(:call) do |server_context:, idempotency_key:, **arguments|
          perform(name, idempotency_key: idempotency_key, server_context: server_context, **arguments)
        end
      end
    end.freeze
  end
end
