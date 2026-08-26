require "test_helper"

class HearthMcp::ManagementToolsTest < ActiveSupport::TestCase
  setup do
    Current.session = sessions(:browser)
    Current.household = households(:home)
    Current.person = people(:two)
    @session = agent_sessions(:connected)
  end

  teardown { Current.reset }

  test "publishes ten recursively closed management contracts without administration or delete tools" do
    assert_equal %w[
      create_person update_person create_recipe update_recipe create_exercise update_exercise
      create_workout_template update_workout_template create_habit update_habit
    ], HearthMcp::ManagementTools::ALL.map(&:tool_name)

    HearthMcp::ManagementTools::ALL.each do |tool|
      assert_closed_schema tool.to_h.fetch(:inputSchema), tool.tool_name
    end
    destructive = HearthMcp::ManagementTools::ALL.filter_map do |tool|
      tool.tool_name if tool.to_h.dig(:annotations, :destructiveHint)
    end
    assert_equal %w[update_recipe update_workout_template update_habit], destructive
  end

  test "capability groups expose only their stable unions and runtime grants remain management free" do
    read = issue_grant(%w[health_read])
    catalog = issue_grant(%w[catalog_manage])
    people = issue_grant(%w[people_manage])
    mixed = issue_grant(%w[health_read catalog_manage people_manage])

    assert_empty names_for(read) & HearthMcp::ManagementTools::ALL.map(&:tool_name)
    assert_equal HearthMcp::ManagementTools::CATALOG.map(&:tool_name), names_for(catalog)
    assert_equal HearthMcp::ManagementTools::PEOPLE.map(&:tool_name), names_for(people)
    assert_equal(
      HearthMcp::Tools::ALL.map(&:tool_name) + HearthMcp::ManagementTools::CATALOG.map(&:tool_name) + HearthMcp::ManagementTools::PEOPLE.map(&:tool_name),
      names_for(mixed)
    )

    @session.update!(status: "starting")
    runtime = @session.issue_runtime_grant!.grant
    assert_equal %w[health_read knowledge_read knowledge_submit], runtime.capability_groups
    assert_empty names_for(runtime) & HearthMcp::ManagementTools::ALL.map(&:tool_name)
  end

  test "every management call stages exactly one exact-capability proposal without writing domain rows" do
    catalog = issue_grant(%w[catalog_manage])
    people = issue_grant(%w[people_manage])
    counts = domain_counts
    arguments = management_arguments

    HearthMcp::ManagementTools::ALL.each.with_index do |tool, index|
      grant = tool.tool_name.end_with?("_person") ? people : catalog
      result = tool.call(**arguments.fetch(tool.tool_name), idempotency_key: "management-stage-#{index}", server_context: { grant: grant })
      assert_not result.error?, "#{tool.tool_name}: #{result.content.inspect}"
      proposal = Agent::MutationProposal.order(:id).last
      assert_equal "pending", proposal.status
      assert_equal(tool.tool_name.end_with?("_person") ? "people.manage" : "catalog.manage", proposal.permission_request.capability)
      assert_equal proposal.input_digest, proposal.preview.dig("basis", "input_digest")
      assert_equal proposal.expected_state_digest, proposal.preview.dig("basis", "expected_state_digest")
      assert_operator JSON.generate(proposal.preview).bytesize, :<=, 64.kilobytes
      assert_nil proposal.execution
    end

    assert_equal 10, Agent::MutationProposal.where(idempotency_key: 10.times.map { |index| "management-stage-#{index}" }).count
    assert_equal counts, domain_counts
  end

  test "mismatched capabilities deny calls before proposal creation" do
    catalog = issue_grant(%w[catalog_manage])
    people = issue_grant(%w[people_manage])
    health = issue_grant(%w[health_write])
    proposal_count = Agent::MutationProposal.count

    denied = [
      HearthMcp::ManagementTools::PEOPLE.first.call(
        name: "Denied", idempotency_key: "catalog-cannot-create-person", server_context: { grant: catalog }
      ),
      HearthMcp::ManagementTools::CATALOG.first.call(
        **recipe_arguments, idempotency_key: "people-cannot-create-recipe", server_context: { grant: people }
      ),
      HearthMcp::ManagementTools::PEOPLE.first.call(
        name: "Denied", idempotency_key: "health-cannot-create-person", server_context: { grant: health }
      )
    ]

    assert denied.all?(&:error?)
    assert_match(/people\.manage authorization is required/, denied.first.content.sole[:text])
    assert_match(/catalog\.manage authorization is required/, denied.second.content.sole[:text])
    assert_equal proposal_count, Agent::MutationProposal.count
  end

  test "create_exercise with muscle targets stages one proposal and writes no domain rows" do
    grant = issue_grant(%w[catalog_manage])
    counts = domain_counts
    target_count = ExerciseMuscleTarget.count
    tool = management_tool("create_exercise")

    result = tool.call(
      **exercise_target_arguments,
      idempotency_key: "stage-exercise-targets",
      server_context: { grant: grant }
    )

    assert_not result.error?, result.content.inspect
    proposal = Agent::MutationProposal.find(result.structured_content.fetch(:proposal_id))
    assert_equal "pending", proposal.status
    assert_equal "catalog.manage", proposal.permission_request.capability
    assert_equal 1, Agent::MutationProposal.where(idempotency_key: "stage-exercise-targets").count
    assert_equal counts, domain_counts
    assert_equal target_count, ExerciseMuscleTarget.count
  end

  test "invalid muscle target requests fail before a proposal is staged" do
    grant = issue_grant(%w[catalog_manage])
    tool = management_tool("create_exercise")
    proposal_count = Agent::MutationProposal.count

    duplicate = tool.call(
      name: "Duplicate targets",
      modality: "strength",
      movement_pattern: "carry",
      muscle_targets: [
        { muscle_key: "glutes", role: "primary" },
        { muscle_key: "glutes", role: "secondary" }
      ],
      idempotency_key: "duplicate-muscle-keys",
      server_context: { grant: grant }
    )
    unknown = tool.call(
      name: "Unknown target",
      modality: "strength",
      movement_pattern: "carry",
      muscle_targets: [ { muscle_key: "not_a_muscle", role: "primary" } ],
      idempotency_key: "unknown-muscle-key",
      server_context: { grant: grant }
    )
    invalid = tool.call(
      name: "Invalid role",
      modality: "strength",
      movement_pattern: "carry",
      muscle_targets: [ { muscle_key: "glutes", role: "assistant" } ],
      idempotency_key: "invalid-muscle-role",
      server_context: { grant: grant }
    )

    assert duplicate.error?
    assert unknown.error?
    assert invalid.error?
    assert_match(/unique/i, duplicate.content.sole[:text])
    assert_match(/Unknown muscle key|not_a_muscle/, unknown.content.sole[:text])
    assert_match(/Invalid muscle target role|assistant/, invalid.content.sole[:text])
    assert_equal proposal_count, Agent::MutationProposal.count
  end

  test "update_exercise rejects a foreign-household exercise id before staging" do
    grant = issue_grant(%w[catalog_manage])
    connection = ActiveRecord::Base.connection
    connection.execute("PRAGMA ignore_check_constraints = ON")
    foreign = Household.new(name: "Foreign household", installation_key: 2)
    foreign.save!(validate: false)
    foreign_exercise = foreign.exercises.create!(name: "Foreign carry", modality: "strength", movement_pattern: "carry")
    connection.execute("PRAGMA ignore_check_constraints = OFF")
    proposal_count = Agent::MutationProposal.count

    result = management_tool("update_exercise").call(
      id: foreign_exercise.id,
      guidance: "Should not stage",
      idempotency_key: "foreign-exercise-update",
      server_context: { grant: grant }
    )

    assert result.error?
    assert_equal proposal_count, Agent::MutationProposal.count
  ensure
    connection&.execute("PRAGMA ignore_check_constraints = OFF")
  end

  test "health.write and people.manage grants cannot call exercise management tools" do
    health = issue_grant(%w[health_write])
    people = issue_grant(%w[people_manage])
    proposal_count = Agent::MutationProposal.count

    denied = [
      management_tool("create_exercise").call(
        **exercise_target_arguments,
        idempotency_key: "health-cannot-create-exercise",
        server_context: { grant: health }
      ),
      management_tool("update_exercise").call(
        id: exercises(:squat).id,
        guidance: "Denied",
        idempotency_key: "people-cannot-update-exercise",
        server_context: { grant: people }
      )
    ]

    assert denied.all?(&:error?)
    assert_match(/catalog\.manage authorization is required/, denied.first.content.sole[:text])
    assert_match(/catalog\.manage authorization is required/, denied.second.content.sole[:text])
    assert_equal proposal_count, Agent::MutationProposal.count
  end

  test "confirmed exercise target execution writes audit snapshots and failed execution leaves no partial rows" do
    grant = issue_grant(%w[catalog_manage])
    staged = management_tool("create_exercise").call(
      **exercise_target_arguments,
      idempotency_key: "audit-exercise-targets",
      server_context: { grant: grant }
    )
    proposal = Agent::MutationProposal.find(staged.structured_content.fetch(:proposal_id))
    execution = proposal.decide!(outcome: "approved", by: users(:two), token: proposal.confirmation_token)
    exercise = Exercise.find(execution.result.fetch("id"))

    assert_equal({}, execution.before_state)
    assert_equal(
      [
        { "muscle_key" => "forearms", "role" => "primary", "position" => 1 },
        { "muscle_key" => "glutes", "role" => "secondary", "position" => 2 }
      ],
      execution.after_state.fetch("muscle_targets")
    )
    assert_equal [ "forearms", "glutes" ], exercise.ordered_muscle_targets.map { |target| target.muscle.key }

    count = Exercise.count
    colliding = management_tool("create_exercise").call(
      name: exercises(:squat).name,
      modality: "strength",
      movement_pattern: "squat",
      muscle_targets: [ { muscle_key: "glutes", role: "primary" } ],
      idempotency_key: "audit-exercise-failure",
      server_context: { grant: grant }
    )
    failed = Agent::MutationProposal.find(colliding.structured_content.fetch(:proposal_id))
    assert_raises(ActiveRecord::RecordInvalid) do
      failed.decide!(outcome: "approved", by: users(:two), token: failed.confirmation_token)
    end
    assert_equal "failed", failed.reload.status
    assert_nil failed.execution
    assert_equal count, Exercise.count
    assert Agent::AuditEvent.exists?(
      subject_type: failed.class.name, subject_id: failed.id, event_type: "mutation.failed"
    )
  end

  test "schema-valid unsourced verified recipe fails through the management tool path" do
    grant = issue_grant(%w[catalog_manage])
    recipe_count = Recipe.count
    result = HearthMcp::ManagementTools::CATALOG.find { |tool| tool.tool_name == "create_recipe" }.call(
      title: "Unsourced verified recipe", provenance_status: "verified",
      ingredients: [ { key: "stock", name: "Stock" } ],
      instructions: [ { body: "Warm", ingredient_keys: [ "stock" ] } ],
      idempotency_key: "tool-unsourced-verified-recipe", server_context: { grant: grant }
    )

    refute result.error?
    proposal = Agent::MutationProposal.find(result.structured_content.fetch(:proposal_id))
    assert_raises(ActiveRecord::RecordInvalid) do
      proposal.decide!(outcome: "approved", by: users(:two), token: proposal.confirmation_token)
    end
    assert_equal "failed", proposal.reload.status
    assert_nil proposal.execution
    assert_equal recipe_count, Recipe.count
  end

  private
    def issue_grant(groups)
      Agent::Grant.issue!(
        conversation: @session.conversation, agent_session: @session,
        capability_groups: groups, expires_at: 10.minutes.from_now
      ).grant
    end

    def names_for(grant) = HearthMcp::Catalog.tools_for(grant).map(&:tool_name)

    def domain_counts
      [ Person.count, Recipe.count, Exercise.count, WorkoutTemplate.count, Habit.count ]
    end

    def management_arguments
      exercise = households(:home).exercises.first
      {
        "create_person" => { name: "Taylor" },
        "update_person" => { id: people(:two).id, name: "Taylor" },
        "create_recipe" => recipe_arguments,
        "update_recipe" => { id: recipes(:porridge).id, title: "Porridge revised" },
        "create_exercise" => { name: "Loaded carry", modality: "strength", movement_pattern: "carry" },
        "update_exercise" => { id: exercise.id, guidance: "Controlled pace" },
        "create_workout_template" => workout_arguments(exercise),
        "update_workout_template" => { id: households(:home).workout_templates.first.id, description: "Revised" },
        "create_habit" => habit_arguments,
        "update_habit" => { id: households(:home).habits.first.id, description: "Revised" }
      }
    end

    def recipe_arguments
      {
        title: "Management soup", provenance_status: "personal",
        ingredients: [ { key: "stock", name: "Vegetable stock", quantity: "2", unit: "cups" } ],
        instructions: [ { body: "Warm gently", ingredient_keys: [ "stock" ] } ]
      }
    end

    def workout_arguments(exercise)
      {
        title: "Management workout", provenance_status: "personal",
        blocks: [ {
          title: "Strength", block_kind: "strength", dose_class: "strength",
          prescriptions: [ { exercise_id: exercise.id, performance_kind: "reps", sets_count: 3, rep_min: 5, rep_max: 8 } ]
        } ]
      }
    end

    def habit_arguments
      {
        name: "Management habit",
        metrics: [ { key: "minutes", label: "Minutes", value_type: "duration", unit: "minutes" } ]
      }
    end

    def assert_closed_schema(schema, label)
      assert_equal false, schema[:additionalProperties], label if schema[:type] == "object"
      schema.fetch(:properties, {}).each_value { |child| assert_closed_schema(child, label) if child.is_a?(Hash) }
      assert_closed_schema(schema[:items], label) if schema[:items].is_a?(Hash)
    end

    def management_tool(name)
      HearthMcp::ManagementTools::ALL.find { |tool| tool.tool_name == name }
    end

    def exercise_target_arguments
      {
        name: "Loaded suitcase carry",
        modality: "strength",
        movement_pattern: "carry",
        muscle_targets: [
          { muscle_key: "forearms", role: "primary" },
          { muscle_key: "glutes", role: "secondary" }
        ]
      }
    end
end
