require "test_helper"

class Agent::MutationProposalTest < ActiveSupport::TestCase
  setup do
    Current.session = sessions(:browser)
    Current.household = households(:home)
    Current.person = people(:two)
    @agent_session = agent_sessions(:connected)
    Agent::OperationalAuthorization.authorize!(agent_session: @agent_session, reason: "Daily operations")
    @agent_session.update!(status: "starting")
    @grant = @agent_session.issue_runtime_grant!.grant
  end

  teardown { Current.reset }

  test "immediate meal aggregate is atomic, 1-based, audited, and replayable" do
    arguments = {
      eaten_on: "2026-07-31",
      notes: "Explicit lunch",
      meal_items: [
        { source_kind: "free_text", snapshot_label: "Toast" },
        { source_kind: "recipe", recipe_id: recipes(:observed_soup).id, recipe_feedback_attributes: { body: "Explicitly enjoyed" } }
      ]
    }
    expected = Agent::Mutation::Operations.expected_state(operation: "create_meal", arguments: arguments, proposal: @grant)

    execution = Agent::MutationProposal.execute_immediate!(
      grant: @grant,
      operation: "create_meal",
      arguments: arguments,
      expected_state: expected,
      idempotency_key: "create-meal-123"
    )
    replay = Agent::MutationProposal.execute_immediate!(
      grant: @grant,
      operation: "create_meal",
      arguments: arguments,
      expected_state: expected,
      idempotency_key: "create-meal-123"
    )

    meal = Meal.find(execution.result.fetch("id"))
    assert_equal [ 1, 2 ], meal.meal_items.map(&:position)
    assert_equal "Explicitly enjoyed", meal.meal_items.second.recipe_feedback.body
    assert_equal execution, replay
    assert_equal 1, Meal.where(id: meal.id).count
    assert_equal({}, execution.before_state)
    assert_equal 2, execution.after_state.fetch("meal_items").size
  end

  test "destructive proposal needs the one-time token and reconstructs the deleted graph" do
    meal = meals(:sam_recipe_target_week)
    expected = Agent::Mutation::Operations.expected_state(
      operation: "delete_meal", arguments: { id: meal.id }, proposal: @grant
    )
    proposal, token = Agent::MutationProposal.propose!(
      grant: @grant, capability: "health.write",
      operation: "delete_meal",
      arguments: { id: meal.id },
      preview: Agent::Mutation::Operations.preview(operation: "delete_meal", arguments: { id: meal.id }, context: @grant),
      expected_state: expected,
      idempotency_key: "delete-meal-123",
      deadline_at: 1.minute.from_now
    )

    assert_equal token, proposal.reload.confirmation_token

    assert_raises(ActiveRecord::RecordInvalid) do
      proposal.decide!(outcome: "approved", by: users(:two), token: "wrong")
    end
    proposal.reload.decide!(outcome: "approved", by: users(:two), token: token)

    assert_equal "executed", proposal.reload.status
    assert_not Meal.exists?(meal.id)
    assert_equal meal.id, proposal.execution.before_state.fetch("id")
    assert_equal({}, proposal.execution.after_state)
    assert_equal users(:two), proposal.execution.executed_by
    assert_equal "approved", proposal.permission_request.reload.status
    assert_raises(ActiveRecord::RecordInvalid) do
      proposal.decide!(outcome: "approved", by: users(:two), token: token)
    end
    assert_equal "executed", proposal.reload.status
  end

  test "nested destroys and existing feedback replacement require confirmation" do
    meal = meals(:sam_recipe_target_week)
    item = meal_items(:sam_soup)
    feedback = item.create_recipe_feedback!(body: "Keep this exact wording")

    assert Agent::Mutation::Operations.consequential?(
      operation: "update_meal",
      arguments: {
        id: meal.id,
        meal_items: [ { id: item.id, source_kind: "recipe", _destroy: true } ]
      },
      context: @grant
    )
    assert Agent::Mutation::Operations.consequential?(
      operation: "update_meal",
      arguments: {
        id: meal.id,
        meal_items: [ {
          id: item.id,
          source_kind: "recipe",
          recipe_feedback_attributes: { id: feedback.id, body: "Replacement wording" }
        } ]
      },
      context: @grant
    )

    session = create_in_progress_training_session
    block = session.training_session_blocks.sole
    assert Agent::Mutation::Operations.consequential?(
      operation: "update_training_session",
      arguments: { id: session.id, blocks: [ { id: block.id, _destroy: true } ] },
      context: @grant
    )
  end

  test "expired and stale proposals fail closed" do
    meal = meals(:sam_recipe_target_week)
    expected = Agent::Mutation::Operations.expected_state(operation: "delete_meal", arguments: { id: meal.id }, proposal: @grant)
    proposal, token = Agent::MutationProposal.propose!(
      grant: @grant, capability: "health.write", operation: "delete_meal", arguments: { id: meal.id }, preview: {}, expected_state: expected,
      idempotency_key: "delete-meal-expired", deadline_at: 1.second.from_now
    )
    proposal.update_column(:deadline_at, 1.second.ago)

    assert_raises(ActiveRecord::RecordInvalid) do
      proposal.decide!(outcome: "approved", by: users(:two), token: token)
    end
    assert_equal "expired", proposal.reload.status
    assert Meal.exists?(meal.id)
  end

  test "completed training deletion remains prohibited" do
    session = training_sessions(:other_person)

    assert_raises(Agent::Mutation::Operations::Prohibited) do
      Agent::Mutation::Operations.execute!(
        operation: "delete_training_session",
        arguments: { id: session.id },
        proposal: @grant
      )
    end
    assert TrainingSession.exists?(session.id)
  end

  test "a linked planned meal cannot be unplanned" do
    plan = planned_meals(:sam_target_week)
    plan.convert_for!(people(:two))

    error = assert_raises(Agent::Mutation::Operations::Prohibited) do
      Agent::Mutation::Operations.execute!(
        operation: "delete_planned_meal",
        arguments: { id: plan.id },
        proposal: @grant
      )
    end

    assert_equal "A logged planned meal must be unlogged separately before it can be unplanned", error.message
    assert PlannedMeal.exists?(plan.id)
  end

  test "planned meal scale is person scoped and previews the decision history a delete would destroy" do
    created = Agent::Mutation::Operations.execute!(
      operation: "create_planned_meal",
      arguments: { planned_on: "2026-08-05", recipe_id: recipes(:salad).id, recipe_scale: 2 },
      proposal: @grant
    )
    plan = PlannedMeal.find(created.dig(:result, "id"))
    assert_equal 2, plan.recipe_scale
    assert_equal [ Rational(2) ], plan.planned_meal_ingredients.active.map(&:quantity)

    Agent::Mutation::Operations.execute!(
      operation: "update_planned_meal",
      arguments: { id: plan.id, recipe_scale: "0.5" },
      proposal: @grant
    )
    assert_equal 0.5, plan.reload.recipe_scale
    assert_equal [ Rational(1, 2) ], plan.planned_meal_ingredients.active.map(&:quantity)

    plan.planned_meal_ingredients.active.sole.decide!(:missing)
    plan.update!(recipe: recipes(:observed_soup))
    preview = Agent::Mutation::Operations.preview(
      operation: "delete_planned_meal", arguments: { "id" => plan.id }, context: @grant
    )
    assert_equal 1, preview.dig("before", "active_ingredient_decisions")
    assert_equal 1, preview.dig("before", "superseded_ingredient_decisions")

    assert_raises(ActiveRecord::RecordInvalid) do
      Agent::Mutation::Operations.execute!(
        operation: "update_planned_meal", arguments: { id: plan.id, recipe_scale: 0 }, proposal: @grant
      )
    end
  end

  test "planned meal logging uses the controlled UTC date boundary and a stable future error" do
    travel_to Time.zone.local(2026, 7, 31, 12) do
      plan = PlannedMeal.create!(
        household: households(:home), person: people(:two), recipe: recipes(:observed_soup),
        planned_on: Date.new(2026, 8, 1)
      )

      error = assert_raises(Agent::Mutation::Operations::Prohibited) do
        Agent::Mutation::Operations.execute!(
          operation: "log_planned_meal", arguments: { id: plan.id }, proposal: @grant
        )
      end

      assert_equal "A planned meal can only be logged on or after its planned date", error.message
      assert_nil plan.reload.converted_meal_for(people(:two))
    end
  end

  test "agent logging and deletion reach the same pantry reservation lifecycle" do
    travel_to Time.zone.local(2026, 7, 31, 12) do
      ingredient = Ingredient.resolve!(household: households(:home), name: "Agent rice")
      stock = PantryItem.for(household: households(:home), ingredient: ingredient).confirm!(
        quantity: 4, unit: "cup", source: "pantry_check", confirmed_by: people(:without_login)
      )
      recipe = households(:home).recipes.create!(
        title: "Agent lifecycle plan", source_name: "Agent fixture", provenance_status: :observed
      )
      recipe.recipe_ingredients.create!(display_name: "Agent rice", display_quantity: "2", unit: "cup", position: 1)
      plan = PlannedMeal.create!(household: households(:home), recipe: recipe, planned_on: Date.new(2026, 7, 31))

      Agent::Mutation::Operations.execute!(operation: "log_planned_meal", arguments: { id: plan.id }, proposal: @grant)
      meal = plan.meals.sole

      assert_equal [ "confirmed", Rational(2) ], [ stock.reload.state, stock.quantity ]
      assert_equal [ Rational(2) ], plan.pantry_consumptions.active.map(&:quantity)

      Agent::Mutation::Operations.execute!(operation: "delete_meal", arguments: { id: meal.id }, proposal: @grant)

      assert_equal [ "confirmed", Rational(4) ], [ stock.reload.state, stock.quantity ]
      assert_equal [ "credited" ], plan.pantry_consumptions.reload.map(&:released_reason)
    end
  end

  test "two sessions may independently reuse the same idempotency key and input" do
    second_session = Agent::Session.create!(
      household: @agent_session.household,
      person: @agent_session.person,
      conversation: @agent_session.conversation,
      installation: @agent_session.installation,
      browser_session: @agent_session.browser_session,
      status: "starting",
      authentication_status: "authenticated",
      mcp_authorization_status: "not_configured"
    )
    Agent::OperationalAuthorization.authorize!(agent_session: second_session, reason: "Second conversation runtime")
    second_grant = second_session.issue_runtime_grant!.grant
    arguments = {
      eaten_on: "2026-07-31",
      meal_items: [ { source_kind: "free_text", snapshot_label: "Independent coffee" } ]
    }

    first = Agent::MutationProposal.execute_immediate!(
      grant: @grant, operation: "create_meal", arguments: arguments,
      expected_state: {}, idempotency_key: "same-session-key"
    )
    second = Agent::MutationProposal.execute_immediate!(
      grant: second_grant, operation: "create_meal", arguments: arguments,
      expected_state: {}, idempotency_key: "same-session-key"
    )

    assert_not_equal first.id, second.id
    assert_equal 2, Meal.joins(:meal_items).where(meal_items: { snapshot_label: "Independent coffee" }).count
  end

  test "revoked staged grant fails closed with a stable reason" do
    meal = meals(:sam_recipe_target_week)
    expected = Agent::Mutation::Operations.expected_state(operation: "delete_meal", arguments: { id: meal.id }, proposal: @grant)
    proposal, token = Agent::MutationProposal.propose!(
      grant: @grant, capability: "health.write", operation: "delete_meal", arguments: { id: meal.id }, preview: {}, expected_state: expected,
      idempotency_key: "revoked-grant-delete", deadline_at: 1.minute.from_now
    )
    @grant.revoke!(reason: "test revocation")

    error = assert_raises(Agent::Grant::AuthorizationRequired) do
      proposal.decide!(outcome: "approved", by: users(:two), token: token)
    end

    assert_equal "The staged operational grant is no longer active", error.message
    assert_equal "The staged operational grant is no longer active", proposal.reload.failure_reason
    assert Meal.exists?(meal.id)
  end

  test "state drift terminalizes an approved proposal without mutating" do
    meal = meals(:sam_recipe_target_week)
    expected = Agent::Mutation::Operations.expected_state(operation: "delete_meal", arguments: { id: meal.id }, proposal: @grant)
    proposal, token = Agent::MutationProposal.propose!(
      grant: @grant, capability: "health.write", operation: "delete_meal", arguments: { id: meal.id }, preview: {}, expected_state: expected,
      idempotency_key: "delete-meal-stale", deadline_at: 1.minute.from_now
    )
    meal.update!(notes: "Changed after preview")

    assert_raises(ActiveRecord::StaleObjectError) do
      proposal.decide!(outcome: "approved", by: users(:two), token: token)
    end

    assert_equal "failed", proposal.reload.status
    assert Meal.exists?(meal.id)
    assert_nil proposal.execution
  end

  test "weekly dose target snapshots retain stale guards for every target column" do
    arguments = { weekly_zone2_minutes_target: 120 }
    expected = Agent::Mutation::Operations.expected_state(
      operation: "update_weekly_dose_targets", arguments: arguments, proposal: @grant
    )
    assert_equal %w[
      weekly_strength_sessions_target weekly_structured_minutes_target
      weekly_vigorous_minutes_target weekly_zone2_minutes_target
    ], expected.keys.grep(/weekly_/).sort

    proposal, token = Agent::MutationProposal.propose!(
      grant: @grant, capability: "health.write", operation: "update_weekly_dose_targets",
      arguments: arguments, preview: {}, expected_state: expected,
      idempotency_key: "weekly-target-stale", deadline_at: 1.minute.from_now
    )
    people(:two).update!(weekly_zone2_minutes_target: 999)

    assert_raises(ActiveRecord::StaleObjectError) do
      proposal.decide!(outcome: "approved", by: users(:two), token: token)
    end
    assert_equal 999, people(:two).reload.weekly_zone2_minutes_target
    assert_equal "failed", proposal.reload.status
    assert_nil proposal.execution
  end

  test "typed plan, training, target, habit configuration, and check-in paths stay person scoped" do
    plan_result = Agent::Mutation::Operations.execute!(
      operation: "create_planned_meal",
      arguments: { planned_on: "2026-08-05", recipe_id: recipes(:observed_soup).id },
      proposal: @grant
    )
    plan = PlannedMeal.find(plan_result.dig(:result, "id"))
    assert_equal people(:two), plan.person

    logged = Agent::Mutation::Operations.execute!(
      operation: "log_planned_meal", arguments: { id: planned_meals(:sam_target_week).id }, proposal: @grant
    )
    replay = Agent::Mutation::Operations.execute!(
      operation: "log_planned_meal", arguments: { id: planned_meals(:sam_target_week).id }, proposal: @grant
    )
    assert_equal logged.dig(:result, "id"), replay.dig(:result, "id")

    session = training_sessions(:other_person)
    Agent::Mutation::Operations.execute!(
      operation: "update_training_session",
      arguments: { id: session.id, notes: "Confirmed completed-session correction" },
      proposal: @grant
    )
    assert_equal "Confirmed completed-session correction", session.reload.notes

    Agent::Mutation::Operations.execute!(
      operation: "update_weekly_dose_targets",
      arguments: { weekly_zone2_minutes_target: 120, weekly_strength_sessions_target: 3 },
      proposal: @grant
    )
    assert_equal [ 120, 3 ], people(:two).reload.values_at(:weekly_zone2_minutes_target, :weekly_strength_sessions_target)

    Agent::Mutation::Operations.execute!(
      operation: "upsert_person_habit",
      arguments: { habit_id: habits(:sauna).id, active: false, sunday: false },
      proposal: @grant
    )
    assert_not person_habits(:sam_sauna).reload.active?
    assert_not person_habits(:sam_sauna).sunday?

    check_in_result = Agent::Mutation::Operations.execute!(
      operation: "create_habit_check_in",
      arguments: {
        person_habit_id: person_habits(:sam_movement).id,
        checked_on: "2026-08-05",
        measurements: [ { habit_metric_id: habit_metrics(:movement_duration).id, duration_value: 15 } ]
      },
      proposal: @grant
    )
    check_in = HabitCheckIn.find(check_in_result.dig(:result, "id"))
    assert_equal 15, check_in.habit_check_in_measurements.sole.duration_value
    assert_equal people(:two), check_in.person_habit.person

    assert_raises(ActiveRecord::RecordNotFound) do
      Agent::Mutation::Operations.execute!(
        operation: "update_planned_meal",
        arguments: { id: planned_meals(:alex_target_week).id, planned_on: "2026-08-06" },
        proposal: @grant
      )
    end
  end


  private
    def create_in_progress_training_session
      TrainingSession.create!(
        household: households(:home),
        person: people(:two),
        snapshot_title: "Pending nested destroy",
        performed_on: Date.new(2026, 7, 31),
        started_at: Time.current,
        training_session_blocks_attributes: [ {
          position: 1,
          snapshot_title: "Strength",
          snapshot_block_kind: "strength",
          snapshot_dose_class: "strength",
          training_session_exercises_attributes: [ {
            position: 1,
            snapshot_name: "Squat",
            snapshot_modality: "strength",
            snapshot_movement_pattern: "squat",
            snapshot_performance_kind: "reps",
            snapshot_dose_class: "strength",
            training_sets_attributes: [ { position: 1, dose_class: "strength", completed: false } ]
          } ]
        } ]
      )
    end
end
