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

  test "runtime ownership persists starting before heartbeat and resets start time" do
    first_start = Time.zone.local(2026, 8, 2, 12)
    second_start = first_start + 1.minute

    Agent::RuntimeStatus.start_all!(owner: "runtime-1", at: first_start)
    status = households(:home).agent_runtime_status
    assert_equal "starting", status.status
    assert_equal "starting", status.state(at: first_start)

    Agent::RuntimeStatus.heartbeat_all!(owner: "runtime-1", at: first_start + 1.second)
    assert_equal first_start, status.reload.started_at
    assert_equal "online", status.state(at: first_start + 1.second)

    Agent::RuntimeStatus.start_all!(owner: "runtime-2", at: second_start)
    assert_equal second_start, status.reload.started_at
    assert_equal "runtime-2", status.owner
  end

  test "starting status becomes recovering when startup stops heartbeating" do
    now = Time.zone.local(2026, 8, 2, 12)
    Agent::RuntimeStatus.start_all!(owner: "runtime", at: now)

    status = households(:home).agent_runtime_status
    assert_equal "starting", status.state(at: now)
    assert_equal "recovering", status.state(at: now + Agent::RuntimeStatus::STALE_AFTER + 1.second)
  end

  test "stale online state is recovering while terminal states remain persisted" do
    now = Time.zone.local(2026, 8, 2, 12)
    Agent::RuntimeStatus.heartbeat_all!(owner: "runtime", at: now)
    status = households(:home).agent_runtime_status

    assert_equal "recovering", status.state(at: now + Agent::RuntimeStatus::STALE_AFTER + 1.second)
    status.update!(status: "failed", failure_category: "runtime_error", stopped_at: now)
    assert_equal "failed", status.state(at: now)
  end

  test "database constraint accepts starting and rejects unknown statuses" do
    status = Agent::RuntimeStatus.create!(household: households(:home), owner: "runtime",
      status: "starting", started_at: Time.current, heartbeat_at: Time.current)
    assert_equal "starting", status.reload.status

    assert_raises(ActiveRecord::StatementInvalid) do
      Agent::RuntimeStatus.connection.execute(
        "UPDATE agent_runtime_statuses SET status = 'unknown' WHERE id = #{status.id}"
      )
    end
  end
end
