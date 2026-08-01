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
    forbidden = %w[delete_person create_household create_user update_password delete_recipe update_record delete_record]
    assert_empty forbidden & HearthMcp::ManagementTools::ALL.map(&:tool_name)
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
    assert_equal %w[health_read], runtime.capability_groups
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
end
