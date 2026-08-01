require "mcp"

module HearthMcp
  module ManagementTools
    ID = MutationTools::ID
    TEXT = MutationTools::TEXT
    SHORT_TEXT = { type: [ "string", "null" ], maxLength: 500 }.freeze
    STATUS = { type: "string", enum: %w[personal verified adapted observed] }.freeze

    RECIPE_INGREDIENT = {
      type: "object",
      properties: {
        id: ID, key: { type: "string", minLength: 1, maxLength: 100 },
        name: { type: "string", minLength: 1, maxLength: 500 }, quantity: SHORT_TEXT,
        unit: SHORT_TEXT, notes: TEXT, gram_weight: { type: [ "number", "null" ], exclusiveMinimum: 0 }
      },
      required: %w[key name], additionalProperties: false
    }.freeze
    RECIPE_INSTRUCTION = {
      type: "object",
      properties: {
        id: ID, body: { type: "string", minLength: 1, maxLength: 10_000 },
        ingredient_keys: { type: "array", uniqueItems: true, items: { type: "string", minLength: 1, maxLength: 100 } },
        duration_amount: { type: [ "number", "null" ], exclusiveMinimum: 0 },
        duration_unit: { type: [ "string", "null" ], enum: [ *RecipeInstruction::DURATION_UNITS, nil ] },
        temperature_amount: { type: [ "number", "null" ] },
        temperature_unit: { type: [ "string", "null" ], enum: [ *RecipeInstruction::TEMPERATURE_UNITS, nil ] }
      },
      required: %w[body ingredient_keys], additionalProperties: false
    }.freeze
    RECIPE = {
      title: { type: "string", minLength: 1, maxLength: 500 }, description: TEXT,
      yield: SHORT_TEXT, serving_count: { type: [ "number", "null" ], exclusiveMinimum: 0 },
      source_name: SHORT_TEXT, source_url: SHORT_TEXT, provenance_status: STATUS,
      ingredients: { type: "array", items: RECIPE_INGREDIENT },
      instructions: { type: "array", items: RECIPE_INSTRUCTION }
    }.freeze

    EXERCISE = {
      name: { type: "string", minLength: 1, maxLength: 500 },
      modality: { type: "string", enum: Exercise::MODALITIES },
      movement_pattern: { type: "string", enum: Exercise::MOVEMENT_PATTERNS },
      equipment: TEXT, guidance: TEXT
    }.freeze

    PRESCRIPTION = {
      type: "object",
      properties: {
        id: ID, exercise_id: ID,
        performance_kind: { type: "string", enum: ExercisePrescription::PERFORMANCE_KINDS },
        sets_count: { type: "integer", minimum: 1 }, rep_min: { type: [ "integer", "null" ], minimum: 1 },
        rep_max: { type: [ "integer", "null" ], minimum: 1 }, work_seconds: { type: [ "integer", "null" ], minimum: 1 },
        rest_seconds: { type: [ "integer", "null" ], minimum: 0 },
        target_distance_amount: { type: [ "number", "null" ], exclusiveMinimum: 0 },
        target_distance_unit: { type: [ "string", "null" ], enum: [ *ExercisePrescription::DISTANCE_UNITS, nil ] },
        target_count: { type: [ "integer", "null" ], minimum: 1 },
        target_count_unit: { type: [ "string", "null" ], enum: [ *ExercisePrescription::COUNT_UNITS, nil ] },
        per_side: { type: "boolean" }, tempo_cue: TEXT,
        target_heart_rate_min: { type: [ "integer", "null" ], minimum: 1 },
        target_heart_rate_max: { type: [ "integer", "null" ], minimum: 1 },
        target_heart_rate_unit: { type: [ "string", "null" ], enum: [ *ExercisePrescription::HEART_RATE_UNITS, nil ] },
        target_rpe: { type: [ "number", "null" ], minimum: 0, maximum: 10 },
        target_rir: { type: [ "number", "null" ], minimum: 0, maximum: 10 },
        load_guidance: TEXT, notes: TEXT,
        dose_class: { type: [ "string", "null" ], enum: [ *WorkoutBlock::DOSE_CLASSES, nil ] }
      },
      required: %w[exercise_id performance_kind sets_count], additionalProperties: false
    }.freeze
    WORKOUT_BLOCK = {
      type: "object",
      properties: {
        id: ID, title: { type: "string", minLength: 1, maxLength: 500 },
        block_kind: { type: "string", enum: WorkoutBlock::BLOCK_KINDS },
        dose_class: { type: "string", enum: WorkoutBlock::DOSE_CLASSES },
        planned_duration_minutes: { type: [ "integer", "null" ], minimum: 1 }, notes: TEXT,
        prescriptions: { type: "array", items: PRESCRIPTION }
      },
      required: %w[title block_kind dose_class prescriptions], additionalProperties: false
    }.freeze
    WORKOUT = {
      title: { type: "string", minLength: 1, maxLength: 500 }, description: TEXT,
      source_name: SHORT_TEXT, source_url: SHORT_TEXT, provenance_status: STATUS,
      blocks: { type: "array", items: WORKOUT_BLOCK }
    }.freeze

    HABIT_METRIC = {
      type: "object",
      properties: {
        id: ID, key: { type: "string", pattern: "^[a-z][a-z0-9_]*$", maxLength: 100 },
        label: { type: "string", minLength: 1, maxLength: 500 },
        value_type: { type: "string", enum: HabitMetric::VALUE_TYPES }, unit: SHORT_TEXT
      },
      required: %w[key label value_type], additionalProperties: false
    }.freeze
    HABIT = {
      name: { type: "string", minLength: 1, maxLength: 500 }, description: TEXT,
      metrics: { type: "array", items: HABIT_METRIC }
    }.freeze

    class Base < MutationTools::Base
      class << self
        def management_contract(name:, capability:, description:, properties:, required: [])
          mutation_contract(name:, description:, properties:, required:)
          define_singleton_method(:call) do |server_context:, idempotency_key:, **arguments|
            perform(name, idempotency_key:, server_context:, capability:, always_stage: true, **arguments)
          end
        end
      end
    end

    DEFINITIONS = {
      "create_person" => [ "people.manage", "Create a household person with name only.", { name: { type: "string", minLength: 1, maxLength: 500 } }, %w[name] ],
      "update_person" => [ "people.manage", "Update a household person's name only.", { id: ID, name: { type: "string", minLength: 1, maxLength: 500 } }, %w[id name] ],
      "create_recipe" => [ "catalog.manage", "Create one complete recipe aggregate.", RECIPE, %w[title provenance_status ingredients instructions] ],
      "update_recipe" => [ "catalog.manage", "Update one complete recipe aggregate.", RECIPE.merge(id: ID), %w[id] ],
      "create_exercise" => [ "catalog.manage", "Create one exercise.", EXERCISE, %w[name modality movement_pattern] ],
      "update_exercise" => [ "catalog.manage", "Update one exercise.", EXERCISE.merge(id: ID), %w[id] ],
      "create_workout_template" => [ "catalog.manage", "Create one complete workout template aggregate.", WORKOUT, %w[title provenance_status blocks] ],
      "update_workout_template" => [ "catalog.manage", "Update one complete workout template aggregate.", WORKOUT.merge(id: ID), %w[id] ],
      "create_habit" => [ "catalog.manage", "Create one complete habit definition.", HABIT, %w[name metrics] ],
      "update_habit" => [ "catalog.manage", "Update one complete habit definition.", HABIT.merge(id: ID), %w[id] ]
    }.freeze

    ALL = DEFINITIONS.map do |name, (capability, description, properties, required)|
      Class.new(Base) { management_contract(name:, capability:, description:, properties:, required:) }
    end.freeze
    PEOPLE = ALL.select { |tool| tool.tool_name.end_with?("_person") }.freeze
    CATALOG = (ALL - PEOPLE).freeze
  end
end
