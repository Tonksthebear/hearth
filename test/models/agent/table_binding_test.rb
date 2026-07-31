require "test_helper"

class Agent::TableBindingTest < ActiveSupport::TestCase
  test "namespaced models bind only to agent tables" do
    assert_equal "sessions", ::Session.table_name
    assert_equal "agent_sessions", Agent::Session.table_name

    {
      Agent::Profile => "agent_profiles",
      Agent::Installation => "agent_installations",
      Agent::Conversation => "agent_conversations",
      Agent::Message => "agent_messages",
      Agent::PermissionRequest => "agent_permission_requests",
      Agent::PermissionDecision => "agent_permission_decisions",
      Agent::ToolActivity => "agent_tool_activities",
      Agent::Grant => "agent_grants",
      Agent::AuditEvent => "agent_audit_events"
    }.each do |model, table|
      assert_equal table, model.table_name
    end
  end

  test "all namespaced fixtures load through fixtures all" do
    assert_predicate agent_profiles(:hearth), :persisted?
    assert_predicate agent_installations(:local), :persisted?
    assert_predicate agent_conversations(:active), :persisted?
    assert_predicate agent_sessions(:connected), :persisted?
    assert_predicate agent_messages(:prompt), :persisted?
    assert_predicate agent_permission_requests(:pending), :persisted?
    assert_predicate agent_permission_decisions(:approved), :persisted?
    assert_predicate agent_tool_activities(:completed), :persisted?
    assert_predicate agent_grants(:active), :persisted?
    assert_predicate agent_audit_events(:conversation_started), :persisted?
  end

  test "schema contains the scoped credential and lifecycle constraints without secret columns" do
    connection = ActiveRecord::Base.connection
    tables = %w[
      agent_profiles agent_installations agent_conversations agent_sessions agent_messages
      agent_permission_requests agent_permission_decisions agent_tool_activities agent_grants
      agent_audit_events
    ]

    assert_empty tables - connection.tables
    assert_includes connection.columns(:agent_grants).map(&:name), "token_digest"
    refute_includes connection.columns(:agent_grants).map(&:name), "token"

    all_columns = tables.flat_map { |table| connection.columns(table).map(&:name) }
    assert_empty all_columns.grep(/\A(?:provider|bearer|auth(?:entication)?_secret)\z/)
    assert connection.indexes(:agent_grants).any? { |index| index.unique && index.columns == [ "token_locator" ] }

    foreign_key_tables = tables.to_h do |table|
      [ table, connection.foreign_keys(table).map(&:to_table) ]
    end
    assert_includes foreign_key_tables["agent_sessions"], "sessions"
    assert_includes foreign_key_tables["agent_grants"], "sessions"
    assert_includes foreign_key_tables["agent_messages"], "agent_conversations"

    check_names = tables.flat_map { |table| connection.check_constraints(table).map(&:name) }
    assert_includes check_names, "agent_sessions_status"
    assert_includes check_names, "agent_sessions_authentication_status"
    assert_includes check_names, "agent_permission_requests_status"
    assert_includes check_names, "agent_tool_activities_status"
  end
end
