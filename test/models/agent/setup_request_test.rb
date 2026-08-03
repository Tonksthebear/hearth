require "test_helper"

class Agent::SetupRequestTest < ActiveSupport::TestCase
  test "web requests require an actor in the household and explicit authentication method" do
    request = Agent::SetupRequest.new(household: households(:home), requested_by: users(:two),
      certified_key: "grok", action: "authenticate", origin: "web", idempotency_key: "auth")

    assert_not request.valid?
    assert_includes request.errors[:authentication_method_id], "must be explicitly selected"
    request.authentication_method_id = "cached_token"
    assert_predicate request, :valid?
  end

  test "enqueue is idempotent and rejects uncertified providers" do
    first = Agent::SetupRequest.enqueue!(household: households(:home), requested_by: users(:two),
      certified_key: "grok", action: "detect", idempotency_key: "one")
    duplicate = Agent::SetupRequest.enqueue!(household: households(:home), requested_by: users(:two),
      certified_key: "grok", action: "disable", idempotency_key: "one")

    assert_equal first, duplicate
    assert_equal "detect", duplicate.action
    assert_raises(ActiveRecord::RecordInvalid) do
      Agent::SetupRequest.enqueue!(household: households(:home), requested_by: users(:two),
        certified_key: "arbitrary", action: "detect", idempotency_key: "bad")
    end
  end

  test "only one runtime claims a request" do
    request = Agent::SetupRequest.enqueue!(household: households(:home), requested_by: users(:two),
      certified_key: "grok", action: "detect", idempotency_key: "claim")

    assert_equal request, Agent::SetupRequest.claim_next!(owner: "one")
    assert_nil Agent::SetupRequest.claim_next!(owner: "two")
    assert_equal "one", request.reload.claimed_by
  end

  test "stale work recovers before dispatch and expires after dispatch" do
    safe = Agent::SetupRequest.enqueue!(household: households(:home), requested_by: users(:two),
      certified_key: "grok", action: "detect", idempotency_key: "safe")
    assert_equal safe, Agent::SetupRequest.claim_next!(owner: "runtime")
    safe.update_columns(lease_expires_at: 1.second.ago)

    Agent::SetupRequest.recover_stale_claims!

    assert_equal "pending", safe.reload.status
    assert_nil safe.dispatched_at
    safe.request_cancel!

    uncertain = Agent::SetupRequest.enqueue!(household: households(:home), requested_by: users(:two),
      certified_key: "grok", action: "authenticate", authentication_method_id: "cached_token", idempotency_key: "uncertain")
    assert_equal uncertain, Agent::SetupRequest.claim_next!(owner: "runtime")
    uncertain.dispatch!
    uncertain.update_columns(lease_expires_at: 1.second.ago)

    Agent::SetupRequest.recover_stale_claims!

    assert_equal "expired", uncertain.reload.status
    assert_equal "authentication_failed", uncertain.error_category
  end

  test "cancellation is limited to undispatched work" do
    pending = Agent::SetupRequest.enqueue!(household: households(:home), requested_by: users(:two),
      certified_key: "grok", action: "detect", idempotency_key: "cancel")
    pending.request_cancel!
    assert_equal "cancelled", pending.reload.status

    running = Agent::SetupRequest.enqueue!(household: households(:home), requested_by: users(:two),
      certified_key: "grok", action: "authenticate", authentication_method_id: "cached_token",
      idempotency_key: "running")
    Agent::SetupRequest.claim_next!(owner: "runtime").dispatch!
    running.reload.request_cancel!
    assert_equal "running", running.reload.status
  end
end
