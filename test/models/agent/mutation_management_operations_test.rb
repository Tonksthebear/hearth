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

  test "recipe preview normalizes ingredient changes and induced instruction reference removals" do
    recipe = execute("create_recipe", {
      title: "Reference preview", provenance_status: "personal",
      ingredients: [
        { key: "stock", name: "Stock", quantity: "2", unit: "cups" }, { key: "salt", name: "Salt" }
      ],
      instructions: [ { body: "Combine", ingredient_keys: %w[stock salt] } ]
    }, "reference-preview-create")
    kept = recipe.recipe_ingredients.find_by!(display_name: "Stock")
    arguments = {
      id: recipe.id,
      ingredients: [ { id: kept.id, key: "stock", name: "Chicken stock", quantity: "3", unit: "cups" } ]
    }

    proposal, token = stage("update_recipe", arguments, "reference-preview-update")
    ingredient_changes = proposal.preview.dig("children", "ingredients", "updated").sole.fetch("changes").index_by { |change| change["field"] }
    instruction_change = proposal.preview.dig("children", "instructions", "updated").sole
      .fetch("changes").find { |change| change["field"] == "ingredient_keys" }

    assert_equal [ "Stock", "Chicken stock" ], ingredient_changes.fetch("display_name").values_at("before", "after")
    assert_equal [ "2", "3" ], ingredient_changes.fetch("display_quantity").values_at("before", "after")
    assert_empty ingredient_changes.keys & %w[key name quantity]
    assert_equal [ kept.form_key ], instruction_change.fetch("after")

    proposal.decide!(outcome: "approved", by: users(:two), token: token)
    recipe.reload
    assert_equal [ "Chicken stock", "3" ], kept.reload.values_at(:display_name, :display_quantity)
    assert_equal [ kept.id ], recipe.recipe_instructions.sole.referenced_recipe_ingredient_ids
  end

  test "workout preview accepts long prescription text without duplicating prescriptions in the block diff" do
    workout = households(:home).workout_templates.joins(workout_blocks: :exercise_prescriptions).first
    block = workout.workout_blocks.joins(:exercise_prescriptions).first
    prescription = block.exercise_prescriptions.first
    notes = "x" * 300
    arguments = {
      id: workout.id,
      blocks: [ {
        id: block.id, title: block.title, block_kind: block.block_kind, dose_class: block.dose_class,
        prescriptions: [ prescription.attributes.symbolize_keys.slice(*prescription_keys).merge(notes:) ]
      } ]
    }

    proposal, = stage("update_workout_template", arguments, "long-prescription-preview")
    prescription_changes = proposal.preview.dig("children", "blocks.#{block.id}.prescriptions")

    assert_empty proposal.preview.dig("children", "blocks", "updated")
    assert_equal 200, prescription_changes.fetch("updated").sole.fetch("changes").find { |change| change["field"] == "notes" }.fetch("after").length
    assert_equal "pending", proposal.status
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

  test "create_exercise persists multiple muscle targets on a personal exercise" do
    exercise = execute("create_exercise", {
      name: "Targeted suitcase carry",
      modality: "strength",
      movement_pattern: "carry",
      muscle_targets: [
        { muscle_key: "forearms", role: "primary" },
        { muscle_key: "glutes", role: "secondary" },
        { muscle_key: "obliques", role: "stabilizer" }
      ]
    }, "create-exercise-targets")

    assert_nil exercise.source_key
    assert_equal(
      [ [ "forearms", "primary" ], [ "obliques", "stabilizer" ], [ "glutes", "secondary" ] ],
      exercise.ordered_muscle_targets.map { |target| [ target.muscle.key, target.role ] }
    )
  end

  test "update_exercise replaces, omits, or clears muscle targets by key presence" do
    exercise = execute("create_exercise", {
      name: "Replacement hinge",
      modality: "strength",
      movement_pattern: "hinge",
      muscle_targets: [
        { muscle_key: "glutes", role: "primary" },
        { muscle_key: "hamstrings", role: "secondary" }
      ]
    }, "replace-targets-create")

    execute("update_exercise", {
      id: exercise.id,
      muscle_targets: [
        { muscle_key: "glutes", role: "secondary" },
        { muscle_key: "erector_spinae", role: "stabilizer" }
      ]
    }, "replace-targets-update")
    assert_equal(
      [ [ "erector_spinae", "stabilizer" ], [ "glutes", "secondary" ] ],
      exercise.reload.ordered_muscle_targets.map { |target| [ target.muscle.key, target.role ] }
    )

    execute("update_exercise", { id: exercise.id, guidance: "Keep the bar close" }, "omit-targets-update")
    assert_equal "Keep the bar close", exercise.reload.guidance
    assert_equal(
      [ [ "erector_spinae", "stabilizer" ], [ "glutes", "secondary" ] ],
      exercise.ordered_muscle_targets.map { |target| [ target.muscle.key, target.role ] }
    )

    execute("update_exercise", { id: exercise.id, muscle_targets: [] }, "clear-targets-update")
    assert_empty exercise.reload.exercise_muscle_targets
  end

  test "exercise snapshots and previews use muscle_key identity and derived display order" do
    exercise = execute("create_exercise", {
      name: "Preview hinge",
      modality: "strength",
      movement_pattern: "hinge",
      muscle_targets: [
        { muscle_key: "glutes", role: "primary" },
        { muscle_key: "hamstrings", role: "secondary" }
      ]
    }, "preview-exercise-create")

    snapshot = Agent::Mutation::ManagementOperations.snapshot(exercise)
    assert_equal(
      [
        { "muscle_key" => "glutes", "role" => "primary", "position" => 1 },
        { "muscle_key" => "hamstrings", "role" => "secondary", "position" => 2 }
      ],
      snapshot.fetch("muscle_targets")
    )

    role_change = {
      id: exercise.id,
      muscle_targets: [
        { muscle_key: "hamstrings", role: "secondary" },
        { muscle_key: "glutes", role: "stabilizer" }
      ]
    }
    proposal, token = stage("update_exercise", role_change, "preview-role-change")
    targets = proposal.preview.dig("children", "muscle_targets")
    assert_equal [ "glutes" ], targets.fetch("updated").map { |row| row["identity"] }
    assert_empty targets.fetch("added")
    assert_empty targets.fetch("removed")
    assert_empty targets.fetch("reordered")

    reorder = {
      id: exercise.id,
      muscle_targets: [
        { muscle_key: "hamstrings", role: "secondary" },
        { muscle_key: "glutes", role: "primary" }
      ]
    }
    reorder_proposal, reorder_token = stage("update_exercise", reorder, "preview-request-reorder")
    reorder_diff = reorder_proposal.preview.dig("children", "muscle_targets")
    assert_empty reorder_diff.fetch("added")
    assert_empty reorder_diff.fetch("removed")
    assert_empty reorder_diff.fetch("updated")
    assert_empty reorder_diff.fetch("reordered")

    execution = reorder_proposal.decide!(outcome: "approved", by: users(:two), token: reorder_token)
    assert_equal snapshot.fetch("muscle_targets"), execution.after_state.fetch("muscle_targets")
    assert_equal snapshot.fetch("muscle_targets"), Agent::Mutation::ManagementOperations.snapshot(exercise.reload).fetch("muscle_targets")

    confirmed = proposal.decide!(outcome: "approved", by: users(:two), token: token)
    assert_equal(
      [
        { "muscle_key" => "glutes", "role" => "stabilizer", "position" => 1 },
        { "muscle_key" => "hamstrings", "role" => "secondary", "position" => 2 }
      ],
      confirmed.after_state.fetch("muscle_targets")
    )
    assert_equal(
      [ [ "glutes", "stabilizer" ], [ "hamstrings", "secondary" ] ],
      exercise.reload.ordered_muscle_targets.map { |target| [ target.muscle.key, target.role ] }
    )
  end

  test "preview order follows persisted muscle display positions not catalog defaults" do
    exercise = execute("create_exercise", {
      name: "Persisted order hinge",
      modality: "strength",
      movement_pattern: "hinge",
      muscle_targets: [
        { muscle_key: "glutes", role: "primary" },
        { muscle_key: "hamstrings", role: "secondary" }
      ]
    }, "persisted-order-create")
    muscles(:hamstrings).update!(display_position: 999)
    muscles(:glutes).update!(display_position: 1000)
    before = Agent::Mutation::ManagementOperations.snapshot(exercise.reload)
    assert_equal %w[hamstrings glutes], before.fetch("muscle_targets").map { |row| row["muscle_key"] }

    proposal, token = stage("update_exercise", {
      id: exercise.id,
      muscle_targets: [
        { muscle_key: "glutes", role: "primary" },
        { muscle_key: "hamstrings", role: "secondary" }
      ]
    }, "persisted-order-noop")
    diff = proposal.preview.dig("children", "muscle_targets")

    assert_empty diff.fetch("added")
    assert_empty diff.fetch("removed")
    assert_empty diff.fetch("updated")
    assert_empty diff.fetch("reordered")

    execution = proposal.decide!(outcome: "approved", by: users(:two), token: token)
    assert_equal before.fetch("muscle_targets"), execution.after_state.fetch("muscle_targets")
    assert_equal before.fetch("muscle_targets"), Agent::Mutation::ManagementOperations.snapshot(exercise.reload).fetch("muscle_targets")
  end

  test "recipe ingredient preview identities stay unchanged after the muscle_key fallback" do
    recipe = execute("create_recipe", {
      title: "Identity soup", provenance_status: "personal",
      ingredients: [ { key: "stock", name: "Stock", quantity: "2", unit: "cups" } ],
      instructions: [ { body: "Warm", ingredient_keys: %w[stock] } ]
    }, "identity-recipe-create")
    ingredient = recipe.recipe_ingredients.sole
    proposal, = stage("update_recipe", {
      id: recipe.id,
      ingredients: [ { id: ingredient.id, key: "stock", name: "Bone stock", quantity: "3", unit: "cups" } ]
    }, "identity-recipe-update")

    updated = proposal.preview.dig("children", "ingredients", "updated").sole
    assert_equal ingredient.id.to_s, updated.fetch("identity")
    refute_match(/muscle/, updated.fetch("identity"))
    assert_empty proposal.preview.dig("children", "ingredients", "added")
    assert_empty proposal.preview.dig("children", "ingredients", "removed")
  end

  test "exercise expected_state includes targets so later target edits make a proposal stale" do
    exercise = execute("create_exercise", {
      name: "Stale hinge",
      modality: "strength",
      movement_pattern: "hinge",
      muscle_targets: [ { muscle_key: "glutes", role: "primary" } ]
    }, "stale-targets-create")
    proposal, token = stage("update_exercise", { id: exercise.id, guidance: "Staged cue" }, "stale-targets-update")
    exercise.replace_muscle_targets!([ { muscle_key: "hamstrings", role: "primary" } ])

    assert_raises(ActiveRecord::StaleObjectError) do
      proposal.decide!(outcome: "approved", by: users(:two), token: token)
    end
    assert_equal "failed", proposal.reload.status
    assert_nil exercise.reload.guidance
  end

  test "invalid muscle targets roll back create_exercise and leave no exercise" do
    count = Exercise.count

    unknown = assert_raises(ArgumentError) do
      execute("create_exercise", {
        name: "Unknown target carry",
        modality: "strength",
        movement_pattern: "carry",
        muscle_targets: [ { muscle_key: "not_a_muscle", role: "primary" } ]
      }, "unknown-target-create")
    end
    invalid = assert_raises(ArgumentError) do
      execute("create_exercise", {
        name: "Invalid role carry",
        modality: "strength",
        movement_pattern: "carry",
        muscle_targets: [ { muscle_key: "glutes", role: "assistant" } ]
      }, "invalid-role-create")
    end

    assert_match(/Unknown muscle key/, unknown.message)
    assert_match(/Invalid muscle target role/, invalid.message)
    assert_equal count, Exercise.count
    refute Exercise.exists?(name: "Unknown target carry")
    refute Exercise.exists?(name: "Invalid role carry")
  end

  test "dropping a source-supplied target records a merge tombstone and does not re-add the muscle" do
    created = Exercise.merge_source_record!(
      household: households(:home),
      record: {
        source_key: "catalog-agent-hinge",
        source_version: "v1",
        name: "Catalog agent hinge",
        modality: "strength",
        movement_pattern: "hinge",
        equipment: "Barbell",
        targets: { "glutes" => "primary", "hamstrings" => "secondary" },
        visuals: [],
        attribution: {
          "creator" => "Workout Guide",
          "creator_url" => "https://example.test/creator",
          "license" => "CC BY-SA 4.0",
          "license_url" => "https://creativecommons.org/licenses/by-sa/4.0/",
          "source_name" => "Workout Guide",
          "source_url" => "https://example.test/source",
          "change_note" => "Initial catalog import"
        }
      }
    )
    exercise = created.exercise

    execute("update_exercise", {
      id: exercise.id,
      muscle_targets: [ { muscle_key: "glutes", role: "primary" } ]
    }, "drop-source-target")
    result = Exercise.merge_source_record!(
      household: households(:home),
      record: {
        source_key: "catalog-agent-hinge",
        source_version: "v1",
        name: "Catalog agent hinge",
        modality: "strength",
        movement_pattern: "hinge",
        equipment: "Barbell",
        targets: { "glutes" => "primary", "hamstrings" => "secondary" },
        visuals: [],
        attribution: {
          "creator" => "Workout Guide",
          "creator_url" => "https://example.test/creator",
          "license" => "CC BY-SA 4.0",
          "license_url" => "https://creativecommons.org/licenses/by-sa/4.0/",
          "source_name" => "Workout Guide",
          "source_url" => "https://example.test/source",
          "change_note" => "Initial catalog import"
        }
      }
    )

    assert_equal [ "glutes" ], result.exercise.ordered_muscle_targets.map { |target| target.muscle.key }
    assert_includes result.exercise.source_snapshot.fetch("removed_target_keys"), "hamstrings"
  end

  private
    def prescription_keys
      %i[
        id exercise_id performance_kind sets_count rep_min rep_max work_seconds rest_seconds
        target_distance_amount target_distance_unit target_count target_count_unit per_side tempo_cue
        target_heart_rate_min target_heart_rate_max target_heart_rate_unit target_rpe target_rir load_guidance notes dose_class
      ]
    end

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
