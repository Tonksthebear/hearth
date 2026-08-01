require "test_helper"

class Agent::MutationManagementOperationsTest < ActiveSupport::TestCase
  setup do
    Current.session = sessions(:browser)
    Current.household = households(:home)
    Current.person = people(:two)
    @session = agent_sessions(:connected)
    @grant = Agent::Grant.issue!(
      conversation: @session.conversation, agent_session: @session,
      capability_groups: %w[catalog_manage people_manage], expires_at: 10.minutes.from_now
    ).grant
  end

  teardown { Current.reset }

  test "confirmed recipe proposal executes once with provenance references and 1-based positions" do
    arguments = {
      title: "Confirmed soup", provenance_status: "adapted", source_name: "Household notebook",
      ingredients: [
        { key: "stock", name: "Stock", quantity: "2", unit: "cups" },
        { key: "salt", name: "Salt", quantity: "1", unit: "tsp" }
      ],
      instructions: [ { body: "Combine", ingredient_keys: %w[stock salt], duration_amount: 5, duration_unit: "minutes" } ]
    }
    proposal, token = stage("create_recipe", arguments, "confirmed-recipe")

    assert_equal "adapted", proposal.preview.dig("scalar_changes").find { |change| change["field"] == "provenance_status" }.fetch("after")
    execution = proposal.decide!(outcome: "approved", by: users(:two), token: token)
    recipe = Recipe.find(execution.result.fetch("id"))

    assert_equal [ 1, 2 ], recipe.recipe_ingredients.map(&:position)
    assert_equal [ 1 ], recipe.recipe_instructions.map(&:position)
    assert_equal %w[Salt Stock], recipe.recipe_instructions.sole.referenced_recipe_ingredients.map(&:display_name).sort
    assert_equal "adapted", recipe.provenance_status
    assert_equal execution, proposal.execute!(by: users(:two))
    assert_equal 1, Recipe.where(id: recipe.id).count

    reversed = recipe.recipe_ingredients.reverse.map do |ingredient|
      {
        id: ingredient.id, key: ingredient.form_key, name: ingredient.display_name,
        quantity: ingredient.display_quantity, unit: ingredient.unit, notes: ingredient.notes,
        gram_weight: ingredient.gram_weight
      }
    end
    update = {
      id: recipe.id,
      ingredients: reversed,
      instructions: recipe.recipe_instructions.map do |instruction|
        { id: instruction.id, body: instruction.body, ingredient_keys: reversed.map { |row| row[:key] } }
      end
    }
    execute("update_recipe", update, "reorder-recipe")
    assert_equal reversed.pluck(:id), recipe.reload.recipe_ingredients.ids
    assert_equal [ 1, 2 ], recipe.recipe_ingredients.map(&:position)
  end

  test "recipe child drift makes a staged aggregate stale" do
    recipe = recipes(:porridge)
    arguments = { id: recipe.id, title: "Staged title" }
    proposal, token = stage("update_recipe", arguments, "stale-recipe")
    recipe.recipe_ingredients.first.update!(notes: "Changed after staging")

    assert_raises(ActiveRecord::StaleObjectError) do
      proposal.decide!(outcome: "approved", by: users(:two), token: token)
    end
    assert_equal "failed", proposal.reload.status
    refute_equal "Staged title", recipe.reload.title
  end

  test "recipe preview includes instruction reference removals induced by an ingredient-only update" do
    recipe = execute("create_recipe", {
      title: "Reference preview", provenance_status: "personal",
      ingredients: [
        { key: "stock", name: "Stock" }, { key: "salt", name: "Salt" }
      ],
      instructions: [ { body: "Combine", ingredient_keys: %w[stock salt] } ]
    }, "reference-preview-create")
    kept = recipe.recipe_ingredients.find_by!(display_name: "Stock")
    arguments = {
      id: recipe.id,
      ingredients: [ { id: kept.id, key: kept.form_key, name: kept.display_name } ]
    }

    proposal, token = stage("update_recipe", arguments, "reference-preview-update")
    instruction_change = proposal.preview.dig("children", "instructions", "updated").sole
      .fetch("changes").find { |change| change["field"] == "ingredient_keys" }
    assert_equal [ kept.form_key ], instruction_change.fetch("after")

    proposal.decide!(outcome: "approved", by: users(:two), token: token)
    assert_equal [ kept.id ], recipe.reload.recipe_instructions.sole.referenced_recipe_ingredient_ids
  end

  test "workout and habit child drift each make their staged aggregate stale" do
    workout = households(:home).workout_templates.first
    workout_proposal, workout_token = stage("update_workout_template", { id: workout.id, title: "Staged workout" }, "stale-workout")
    workout.workout_blocks.first.update!(notes: "Changed after staging")

    assert_raises(ActiveRecord::StaleObjectError) do
      workout_proposal.decide!(outcome: "approved", by: users(:two), token: workout_token)
    end
    refute_equal "Staged workout", workout.reload.title

    habit = households(:home).habits.joins(:habit_metrics).first
    habit_proposal, habit_token = stage("update_habit", { id: habit.id, name: "Staged habit" }, "stale-habit")
    habit.habit_metrics.first.update!(label: "Changed after staging")

    assert_raises(ActiveRecord::StaleObjectError) do
      habit_proposal.decide!(outcome: "approved", by: users(:two), token: habit_token)
    end
    refute_equal "Staged habit", habit.reload.name
  end

  test "management operations create all owned aggregate kinds atomically" do
    exercise = execute("create_exercise", { name: "Suitcase carry", modality: "strength", movement_pattern: "carry" }, "exercise")
    workout = execute("create_workout_template", {
      title: "Carry day", provenance_status: "personal",
      blocks: [ { title: "Work", block_kind: "strength", dose_class: "strength", prescriptions: [
        { exercise_id: exercise.id, performance_kind: "duration", sets_count: 2, work_seconds: 30 }
      ] } ]
    }, "workout")
    habit = execute("create_habit", {
      name: "Hydration review", metrics: [ { key: "glasses", label: "Glasses", value_type: "number", unit: "count" } ]
    }, "habit")
    person = execute("create_person", { name: "Morgan" }, "person")

    assert_equal [ 1 ], workout.workout_blocks.map(&:position)
    assert_equal [ 1 ], workout.workout_blocks.sole.exercise_prescriptions.map(&:position)
    assert_equal [ 1 ], habit.habit_metrics.map(&:position)
    assert_equal households(:home), person.household
  end

  test "management updates preserve nested desired order and scalar allowlists" do
    exercise = execute("create_exercise", { name: "Step up", modality: "strength", movement_pattern: "lunge" }, "update-exercise-create")
    execute("update_exercise", { id: exercise.id, name: "Weighted step up", guidance: "Drive through the foot" }, "update-exercise")
    assert_equal [ "Weighted step up", "Drive through the foot" ], exercise.reload.values_at(:name, :guidance)

    workout = execute("create_workout_template", {
      title: "Two blocks", provenance_status: "personal", blocks: [
        { title: "First", block_kind: "strength", dose_class: "strength", prescriptions: [
          { exercise_id: exercise.id, performance_kind: "reps", sets_count: 2, rep_min: 5 }
        ] },
        { title: "Second", block_kind: "cooldown_recovery", dose_class: "none", prescriptions: [
          { exercise_id: exercise.id, performance_kind: "duration", sets_count: 1, work_seconds: 60 }
        ] }
      ]
    }, "update-workout-create")
    blocks = workout.workout_blocks.reverse.map do |block|
      {
        id: block.id, title: block.title, block_kind: block.block_kind, dose_class: block.dose_class,
        planned_duration_minutes: block.planned_duration_minutes, notes: block.notes,
        prescriptions: block.exercise_prescriptions.map do |row|
          row.attributes.symbolize_keys.slice(*%i[
            id exercise_id performance_kind sets_count rep_min rep_max work_seconds rest_seconds
            target_distance_amount target_distance_unit target_count target_count_unit per_side tempo_cue
            target_heart_rate_min target_heart_rate_max target_heart_rate_unit target_rpe target_rir load_guidance notes dose_class
          ])
        end
      }
    end
    execute("update_workout_template", { id: workout.id, blocks: blocks }, "update-workout")
    assert_equal blocks.pluck(:id), workout.reload.workout_blocks.ids
    assert_equal [ 1, 2 ], workout.workout_blocks.map(&:position)

    habit = execute("create_habit", {
      name: "Two metrics", metrics: [
        { key: "score", label: "Score", value_type: "number", unit: "points" },
        { key: "minutes", label: "Minutes", value_type: "duration", unit: "minutes" }
      ]
    }, "update-habit-create")
    metrics = habit.habit_metrics.reverse.map { |row| row.attributes.symbolize_keys.slice(:id, :key, :label, :value_type, :unit) }
    execute("update_habit", { id: habit.id, metrics: metrics }, "update-habit")
    assert_equal metrics.pluck(:id), habit.reload.habit_metrics.ids
    assert_equal [ 1, 2 ], habit.habit_metrics.map(&:position)

    person = people(:two)
    execute("update_person", { id: person.id, name: "Updated household member" }, "update-person")
    assert_equal "Updated household member", person.reload.name
  end

  test "cross-household-style missing nested ids fail without partial writes" do
    exercise_count = Exercise.count
    error = assert_raises(ActiveRecord::RecordNotFound) do
      execute("create_workout_template", {
        title: "Invalid", provenance_status: "personal",
        blocks: [ { title: "Work", block_kind: "strength", dose_class: "strength", prescriptions: [
          { exercise_id: Exercise.maximum(:id) + 10_000, performance_kind: "reps", sets_count: 1, rep_min: 1 }
        ] } ]
      }, "invalid-workout")
    end
    assert_match(/couldn't find Exercise/i, error.message)
    assert_equal exercise_count, Exercise.count
    refute WorkoutTemplate.exists?(title: "Invalid")
  end

  test "foreign-household exercise references fail without partial writes" do
    connection = ActiveRecord::Base.connection
    connection.execute("PRAGMA ignore_check_constraints = ON")
    foreign = Household.new(name: "Foreign household", installation_key: 2)
    foreign.save!(validate: false)
    foreign_exercise = foreign.exercises.create!(name: "Foreign carry", modality: "strength", movement_pattern: "carry")
    connection.execute("PRAGMA ignore_check_constraints = OFF")

    proposal, token = stage("create_workout_template", {
      title: "Foreign reference", provenance_status: "personal",
      blocks: [ { title: "Work", block_kind: "strength", dose_class: "strength", prescriptions: [
        { exercise_id: foreign_exercise.id, performance_kind: "reps", sets_count: 1, rep_min: 1 }
      ] } ]
    }, "foreign-reference")

    assert_raises(ActiveRecord::RecordNotFound) do
      proposal.decide!(outcome: "approved", by: users(:two), token: token)
    end
    assert_equal "failed", proposal.reload.status
    assert_nil proposal.execution
    refute WorkoutTemplate.exists?(title: "Foreign reference")
  ensure
    connection&.execute("PRAGMA ignore_check_constraints = OFF")
  end

  test "catalog attribution and typed metric failures roll back proposal execution and domain writes" do
    invalid_cases = {
      "invalid-recipe-attribution" => [ "create_recipe", {
        title: "Unsourced verified recipe", provenance_status: "verified", ingredients: [], instructions: []
      }, Recipe ],
      "invalid-workout-attribution" => [ "create_workout_template", {
        title: "Unsourced adapted workout", provenance_status: "adapted", blocks: []
      }, WorkoutTemplate ],
      "invalid-number-unit" => [ "create_habit", {
        name: "Unitless number", metrics: [ { key: "score", label: "Score", value_type: "number", unit: nil } ]
      }, Habit ],
      "invalid-boolean-unit" => [ "create_habit", {
        name: "Unitful boolean", metrics: [ { key: "done", label: "Done", value_type: "boolean", unit: "yes/no" } ]
      }, Habit ]
    }

    invalid_cases.each do |key, (operation, arguments, klass)|
      domain_count = klass.count
      proposal, token = stage(operation, arguments, key)
      assert_raises(ActiveRecord::RecordInvalid, key) do
        proposal.decide!(outcome: "approved", by: users(:two), token: token)
      end
      assert_equal "failed", proposal.reload.status, key
      assert_nil proposal.execution, key
      assert_equal domain_count, klass.count, key
      assert Agent::AuditEvent.exists?(
        subject_type: proposal.class.name, subject_id: proposal.id, event_type: "mutation.failed"
      ), key
    end
  end

  test "recorded habit metric schema remains immutable through management updates" do
    habit = habits(:sauna)
    metrics = habit.habit_metrics.map do |metric|
      metric.attributes.symbolize_keys.slice(:id, :key, :label, :value_type, :unit)
    end
    metrics.first[:unit] = "seconds"
    proposal, token = stage("update_habit", { id: habit.id, metrics: metrics }, "immutable-habit-metric")

    assert_raises(ActiveRecord::RecordInvalid) do
      proposal.decide!(outcome: "approved", by: users(:two), token: token)
    end
    assert_equal "failed", proposal.reload.status
    assert_nil proposal.execution
    refute_equal "seconds", habit.reload.habit_metrics.first.unit
  end

  test "lost exact management capability fails closed" do
    proposal, token = stage("create_person", { name: "Capability lost" }, "lost-people-capability")
    @grant.update!(capability_groups: %w[catalog_manage])

    assert_raises(Agent::Grant::AuthorizationRequired) do
      proposal.decide!(outcome: "approved", by: users(:two), token: token)
    end
    assert_equal "failed", proposal.reload.status
    refute Person.exists?(name: "Capability lost")
  end

  test "management preview contract rejects oversized long-summary and malformed diffs atomically" do
    operation = "create_person"
    arguments = { name: "Preview validation" }
    expected = {}
    base = Agent::Mutation::Operations.preview(operation:, arguments:, context: @grant)
    invalid_previews = {
      "oversized-preview" => base.deep_merge("children" => {
        "rows" => { "added" => [ { "label" => "x" * 70.kilobytes } ], "removed" => [], "updated" => [], "reordered" => [] }
      }),
      "long-preview-summary" => base.merge("summary" => "x" * 201),
      "long-nested-summary" => base.deep_merge("children" => {
        "rows" => { "added" => [ { "label" => "x" * 201 } ], "removed" => [], "updated" => [], "reordered" => [] }
      }),
      "malformed-preview" => base.except("scalar_changes")
    }

    invalid_previews.each do |key, preview|
      counts = [ Agent::MutationProposal.count, Agent::PermissionRequest.count, Agent::AuditEvent.count ]
      error = assert_raises(ActiveRecord::RecordInvalid, key) do
        Agent::MutationProposal.propose!(
          grant: @grant, capability: "people.manage", operation:, arguments:, preview:, expected_state: expected,
          idempotency_key: key, deadline_at: 1.minute.from_now
        )
      end
      assert_match(/Preview/, error.message)
      assert_equal counts, [ Agent::MutationProposal.count, Agent::PermissionRequest.count, Agent::AuditEvent.count ], key
    end


    assert_raises(ArgumentError) do
      Agent::MutationProposal.propose!(
        grant: @grant, capability: "catalog.manage", operation:, arguments:, preview: base, expected_state: expected,
        idempotency_key: "mismatched-preview-capability", deadline_at: 1.minute.from_now
      )
    end
    refute Agent::MutationProposal.exists?(idempotency_key: "mismatched-preview-capability")
  end

  private
    def stage(operation, arguments, key)
      expected = Agent::Mutation::Operations.expected_state(operation:, arguments:, proposal: @grant)
      Agent::MutationProposal.propose!(
        grant: @grant, capability: HearthMcp::ManagementTools.capability_for(operation),
        operation:, arguments:, preview: Agent::Mutation::Operations.preview(operation:, arguments:, context: @grant),
        expected_state: expected, idempotency_key: key, deadline_at: 1.minute.from_now
      )
    end

    def execute(operation, arguments, key)
      proposal, token = stage(operation, arguments, key)
      execution = proposal.decide!(outcome: "approved", by: users(:two), token: token)
      execution.result.fetch("type").constantize.find(execution.result.fetch("id"))
    end
end
