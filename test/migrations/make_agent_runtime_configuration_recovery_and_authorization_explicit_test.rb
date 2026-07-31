require "test_helper"
require Rails.root.join(
  "db/migrate/20260730050000_make_agent_runtime_configuration_recovery_and_authorization_explicit"
)

class MakeAgentRuntimeConfigurationRecoveryAndAuthorizationExplicitTest < ActiveSupport::TestCase
  test "cold migration converts a legacy launch string into executable and argv columns" do
    profile = agent_profiles(:hearth)
    profile.update_columns(
      executable_path: "/usr/local/bin/grok agent stdio --label 'Hearth Agent'",
      arguments: []
    )
    migration = MakeAgentRuntimeConfigurationRecoveryAndAuthorizationExplicit.new

    migration.send(:split_legacy_launch_commands!)

    assert_equal "/usr/local/bin/grok", profile.reload.executable_path
    assert_equal [ "agent", "stdio", "--label", "Hearth Agent" ], profile.arguments
  end

  test "cold migration rejects legacy shell operators instead of preserving a hidden shell path" do
    profile = agent_profiles(:hearth)
    profile.update_columns(executable_path: "grok agent stdio | tee output", arguments: [])
    migration = MakeAgentRuntimeConfigurationRecoveryAndAuthorizationExplicit.new

    assert_raises(RuntimeError) { migration.send(:split_legacy_launch_commands!) }
  end
end
