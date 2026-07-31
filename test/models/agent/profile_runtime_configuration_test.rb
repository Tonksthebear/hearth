require "test_helper"
require "tmpdir"

class Agent::ProfileRuntimeConfigurationTest < ActiveSupport::TestCase
  test "builds argv and an allowlisted environment without shell parsing" do
    profile = agent_profiles(:hearth)
    profile.update!(
      executable_path: "/usr/local/bin/agent",
      arguments: [ "stdio", "--json" ],
      environment_keys: %w[ HOME AGENT_TOKEN ]
    )

    assert_equal [ "/usr/local/bin/agent", "stdio", "--json" ], profile.argv
    assert_equal(
      { "HOME" => "/instance/home", "AGENT_TOKEN" => "opaque" },
      profile.environment_from(
        "HOME" => "/instance/home",
        "AGENT_TOKEN" => "opaque",
        "UNRELATED_SECRET" => "excluded"
      )
    )
    refute_includes profile.environment_from("UNRELATED_SECRET" => "excluded"), "UNRELATED_SECRET"
  end

  test "contains the configured working directory within the selected instance" do
    Dir.mktmpdir("hearth-profile-root") do |root|
      profile = agent_profiles(:hearth)
      profile.update!(working_directory: "agents/grok")
      assert_equal File.join(root, "agents/grok"), profile.working_directory_for(root)

      profile.update_column(:working_directory, "../outside")
      assert_raises(ArgumentError) { profile.working_directory_for(root) }
    end
  end

  test "rejects shell-shaped argv and automatic update policy" do
    profile = agent_profiles(:hearth)
    profile.arguments = "stdio --json"
    assert_not profile.valid?
    assert_includes profile.errors[:arguments], "must contain argv strings"

    assert_raises(ActiveRecord::StatementInvalid) do
      profile.update_columns(update_policy: "automatic")
    end
  end
end
