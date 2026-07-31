require "test_helper"

class Agent::ContextTest < ActiveSupport::TestCase
  test "conversation rejects person and profile from another household" do
    other_household = Household.new(name: "Other")
    other_person = other_household.people.build(name: "Other person")
    other_profile = Agent::Profile.new(
      household: other_household,
      name: "Other agent",
      launch_command: "agent"
    )
    conversation = Agent::Conversation.new(
      household: households(:home),
      person: other_person,
      profile: other_profile,
      title: "Wrong context"
    )

    assert_not conversation.valid?
    assert_includes conversation.errors[:person], "must belong to this household"
    assert_includes conversation.errors[:profile], "must belong to this household"
  end

  test "direct foreign key assignment cannot cross conversation context" do
    message = agent_messages(:prompt)
    message.person_id = 0

    assert_not message.valid?
    assert_includes message.errors[:person], "must belong to this household"
    assert_includes message.errors[:conversation], "must match this household and person"
  end

  test "stored conversation session and message context is immutable" do
    [
      agent_conversations(:active),
      agent_sessions(:connected),
      agent_messages(:prompt)
    ].each do |record|
      record.person_id = people(:one).id
      assert_not record.valid?
      assert_includes record.errors[:base], "Agent context cannot be changed"
    end
  end

  test "installation stores generic ACP snapshots without authentication secrets" do
    installation = agent_installations(:local)

    assert_equal 1, installation.protocol_version
    assert_equal true, installation.advertised_capabilities["mcpCapabilities"]["http"]
    assert_equal "cached_token", installation.authentication_methods.first["id"]
    assert installation.valid?
    assert_not installation.attributes.key?("provider")
    assert_not installation.attributes.key?("authentication_secret")

    installation.authentication_methods = [ { "access_token" => "secret-value" } ]
    assert_not installation.valid?
    assert_includes installation.errors[:base], "Authentication and capability snapshots cannot contain secrets"
  end

  test "profile accepts environment names but not environment values" do
    profile = agent_profiles(:hearth)
    profile.environment_keys = [ "API_TOKEN" ]
    assert profile.valid?

    profile.environment_keys = [ { "API_TOKEN" => "secret" } ]
    assert_not profile.valid?
  end
end
