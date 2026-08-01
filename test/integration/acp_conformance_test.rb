require "test_helper"
require "json"
require "rbconfig"
require "tmpdir"

class AcpConformanceTest < ActiveSupport::TestCase
  test "deterministic fake peer enters through the production supervisor and emits sanitized evidence" do
    profile = agent_profiles(:hearth)
    profile.update!(
      executable_path: RbConfig.ruby,
      arguments: [ Rails.root.join("test/fixtures/files/acp/fake_agent.rb").to_s ],
      environment_keys: [ "FAKE_ACP_MODE" ]
    )
    original_mode = ENV["FAKE_ACP_MODE"]
    ENV["FAKE_ACP_MODE"] = "conformance"
    Dir.mktmpdir("hearth-conformance") do |root|
      instance = Hearth::Instance.new(root).initialize!
      output = Acp::Conformance.new(
        instance: instance,
        profile: profile,
        conversation: agent_conversations(:active)
      ).run!
      row = JSON.parse(output)

      assert_equal "hearth_acp_conformance/v1", row["evidence_schema"]
      assert_equal "passed", row["outcome"]
      assert_equal 1, row["protocol_version"]
      assert_equal "not_required", row["authenticated"]
      assert_equal [], row["unverified"]
      assert_equal true, row.dig("checks", "session_new")
      assert_equal true, row.dig("checks", "prompt_completed")
      assert_equal true, row.dig("checks", "acknowledgement_observed")
      assert_equal true, row.dig("checks", "requested_mcp_tools_succeeded")
      assert_equal true, row.dig("checks", "only_allowed_mcp_tools")
      assert_includes %w[http stdio], row["mcp_transport"]
      refute_includes output, "HEARTH_ACP_CERTIFIED_OK"
      refute_includes output, root
      refute_includes output, "fake-session"
      refute_match(/Bearer|HEARTH_MCP_BEARER/, output)
      assert_predicate instance, :stopped?
    end
  ensure
    ENV["FAKE_ACP_MODE"] = original_mode
  end

  test "missing certification acknowledgement produces degraded evidence" do
    profile = agent_profiles(:hearth)
    profile.update!(
      executable_path: RbConfig.ruby,
      arguments: [ Rails.root.join("test/fixtures/files/acp/fake_agent.rb").to_s ],
      environment_keys: [ "FAKE_ACP_MODE" ]
    )
    original_mode = ENV["FAKE_ACP_MODE"]
    ENV["FAKE_ACP_MODE"] = "conformance_missing_ack"

    Dir.mktmpdir("hearth-conformance-degraded") do |root|
      output = Acp::Conformance.new(
        instance: Hearth::Instance.new(root).initialize!,
        profile: profile,
        conversation: agent_conversations(:active)
      ).run!
      row = JSON.parse(output)

      assert_equal "degraded", row["outcome"]
      assert_equal false, row.dig("checks", "acknowledgement_observed")
      assert_includes row["unverified"], "acknowledgement_observed"
    end
  ensure
    ENV["FAKE_ACP_MODE"] = original_mode
  end
end
