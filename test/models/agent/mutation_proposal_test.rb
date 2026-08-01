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
      grant: @grant,
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

  test "expired and stale proposals fail closed" do
    meal = meals(:sam_recipe_target_week)
    expected = Agent::Mutation::Operations.expected_state(operation: "delete_meal", arguments: { id: meal.id }, proposal: @grant)
    proposal, token = Agent::MutationProposal.propose!(
      grant: @grant, operation: "delete_meal", arguments: { id: meal.id }, preview: {}, expected_state: expected,
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

  test "state drift terminalizes an approved proposal without mutating" do
    meal = meals(:sam_recipe_target_week)
    expected = Agent::Mutation::Operations.expected_state(operation: "delete_meal", arguments: { id: meal.id }, proposal: @grant)
    proposal, token = Agent::MutationProposal.propose!(
      grant: @grant, operation: "delete_meal", arguments: { id: meal.id }, preview: {}, expected_state: expected,
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
end
