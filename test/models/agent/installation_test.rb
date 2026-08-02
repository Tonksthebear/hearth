require "test_helper"

class Agent::InstallationTest < ActiveSupport::TestCase
  test "not required round trips while out of set statuses fail at the database" do
    installation = agent_installations(:local)
    installation.require_authentication!
    assert_equal "not_required", installation.reload.authentication_status if installation.authentication_methods.empty?

    installation.update!(authentication_methods: [], authentication_status: "not_required")
    assert_equal "not_required", installation.reload.authentication_status
    assert_raises(ActiveRecord::StatementInvalid) do
      Agent::Installation.where(id: installation.id).update_all(authentication_status: "inferred")
    end
  end

  test "approval persists only complete allowlisted metadata" do
    installation = agent_installations(:local)
    installation.update!(
      authentication_methods: [ { "id" => "cached_token", "name" => "Cached login" } ],
      authentication_status: "required",
      authentication_method_id: nil,
      authentication_approved_at: nil,
      authentication_origin: nil
    )
    installation.approve_authentication!(method_id: "cached_token")

    assert_equal "cached_token", installation.approved_authentication_method
    assert_equal "operator_command", installation.authentication_origin
    assert_predicate installation.authentication_approved_at, :present?
    assert_equal %w[authentication_approved_at authentication_method_id authentication_origin],
      installation.attributes.keys.grep(/authentication_(approved|method_id|origin)/).sort
    refute_includes installation.attributes.to_json, "sk-live"
  end

  test "observation retains the last reported version when agent info is omitted" do
    installation = agent_installations(:local)
    installation.update!(agent_version: "agent 1.2.3")

    installation.observe!(
      protocol_version: 1,
      capabilities: {},
      authentication_methods: [],
      authentication_status: "not_required",
      agent_version: nil
    )

    assert_equal "agent 1.2.3", installation.reload.agent_version
  end

  test "authentication method descriptions are not persisted" do
    installation = agent_installations(:local)

    installation.authentication_methods = [
      { "id" => "cached_token", "name" => "Cached login", "description" => "credential path" }
    ]

    refute_predicate installation, :valid?
    assert_includes installation.errors[:authentication_methods], "must contain ACP method metadata only"
  end
end
