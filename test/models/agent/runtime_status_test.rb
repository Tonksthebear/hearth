require "test_helper"

class Agent::RuntimeStatusTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers

  test "online status becomes stale after the heartbeat threshold" do
    travel_to Time.zone.local(2026, 8, 2, 12) do
      Agent::RuntimeStatus.heartbeat_all!(owner: "runtime")
      status = households(:home).agent_runtime_status
      assert_predicate status, :online?

      travel Agent::RuntimeStatus::STALE_AFTER + 1.second
      assert_predicate status, :stale?
      assert_not status.online?
    end
  end

  test "runtime stop persists a truthful terminal state" do
    Agent::RuntimeStatus.heartbeat_all!(owner: "runtime")
    Agent::RuntimeStatus.stop_all!(owner: "runtime")

    status = households(:home).agent_runtime_status.reload
    assert_equal "stopped", status.status
    assert_not status.online?
  end
end
