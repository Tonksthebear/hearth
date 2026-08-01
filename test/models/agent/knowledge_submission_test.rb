require "test_helper"

class Agent::KnowledgeSubmissionTest < ActiveSupport::TestCase
  FakeClient = Struct.new(:calls, :state, keyword_init: true) do
    def submit(**arguments)
      calls << arguments
      {
        "submission_id" => "submission_v1_test",
        "state" => state || "materialized",
        "updated_at" => 1
      }
    end

    def submission_status(submission_id)
      calls << { submission_id: submission_id }
      { "submission_id" => submission_id, "state" => state || "complete", "updated_at" => 2 }
    end
  end

  setup do
    @session = create_runtime_session
    @grant = @session.issue_runtime_grant!.grant
    @message = Agent::Message.create!(
      household: @grant.household,
      person: @grant.person,
      conversation: @grant.conversation,
      agent_session: @session,
      role: "user",
      body: "Please remember this",
      body_digest: Digest::SHA256.hexdigest("Please remember this")
    )
  end

  test "stages one redacted exact-context submission without contacting Lorester" do
    fake = FakeClient.new(calls: [])
    other_person = people(:one)
    content = "#{@grant.person.name} at #{@grant.person.user.email_address} and #{other_person.name} at #{other_person.user.email_address} prefer a cool bedroom"

    with_stubbed_method(Lorester::Client, :new, fake) do
      first = propose(content: content)
      replay = propose(content: content)

      assert_equal first, replay
      assert_empty fake.calls
      assert_equal "pending", first.status
      assert_equal "pending", first.permission_request.status
      refute_includes first.content.downcase, @grant.person.name.downcase
      refute_includes first.content, @grant.person.user.email_address
      refute_includes first.content.downcase, other_person.name.downcase
      refute_includes first.content, other_person.user.email_address
      assert_includes first.content, "[redacted]"
      assert_equal Digest::SHA256.hexdigest(first.content), first.content_digest
    end
  end

  test "durable approval dispatches once with the deciding actor and bounded provenance" do
    fake = FakeClient.new(calls: [])
    submission = propose

    with_stubbed_method(Lorester::Client, :new, fake) do
      decision = submission.permission_request.decide!(outcome: "approved", by: users(:two))
      submission.dispatch_approved_subject!

      assert_equal users(:two), decision.decided_by
      assert_equal 1, fake.calls.size
      assert_equal "materialized", submission.reload.status
      assert_equal "submission_v1_test", submission.lorester_submission_id
      assert_equal 1, submission.provenance["contract_version"]
      event = Agent::AuditEvent.where(subject_type: "Agent::KnowledgeSubmission", subject_id: submission.id, event_type: "knowledge.submission_dispatched").sole
      assert_equal users(:two), event.actor
      assert_equal submission.lorester_submission_id, event.metadata["submission_id"]
    end
  end

  test "failed dispatch releases its claim and retries with the same request identity" do
    submission = propose
    calls = []
    fake = Object.new
    fake.define_singleton_method(:submit) do |**arguments|
      calls << arguments
      raise Lorester::Client::Error.new("unavailable", "temporary outage") if calls.one?

      { "submission_id" => "submission_v1_retry", "state" => "materialized", "updated_at" => 2 }
    end

    with_stubbed_method(Lorester::Client, :new, fake) do
      assert_raises(Lorester::Client::Error) do
        submission.permission_request.decide!(outcome: "approved", by: users(:two))
      end
      assert_equal "approved", submission.permission_request.reload.status
      assert_nil submission.reload.dispatched_at

      submission.dispatch_approved_subject!
    end

    assert_equal 2, calls.size
    assert_equal [ submission.request_id ] * 2, calls.pluck(:request_id)
    assert_equal "materialized", submission.reload.status
    assert_equal "submission_v1_retry", submission.lorester_submission_id
  end

  test "denial cancellation and elapsed deadline never dispatch" do
    fake = FakeClient.new(calls: [])
    denied = propose(request_id: "knowledge-denied")
    cancelled = propose(request_id: "knowledge-cancelled")
    expired = propose(request_id: "knowledge-expired", deadline_at: 1.second.ago)

    with_stubbed_method(Lorester::Client, :new, fake) do
      denied.permission_request.decide!(outcome: "denied", by: users(:two))
      cancelled.permission_request.cancel!(reason: "not now")
      error = assert_raises(ActiveRecord::RecordInvalid) do
        expired.permission_request.decide!(outcome: "approved", by: users(:two))
      end

      assert_includes error.record.errors[:status], "permission deadline passed"
      assert_equal "expired", expired.permission_request.reload.status
      assert_nil expired.permission_request.decision
      assert_empty fake.calls
    end
  end

  test "status polling is no faster than once per second" do
    fake = FakeClient.new(calls: [])
    submission = propose
    with_stubbed_method(Lorester::Client, :new, fake) do
      submission.permission_request.decide!(outcome: "approved", by: users(:two))
      fake.calls.clear
      submission.reload
      submission.refresh_status!
      submission.refresh_status!
      assert_equal 1, fake.calls.size

      travel 2.seconds
      submission.refresh_status!
      assert_equal 2, fake.calls.size
    end
  end

  test "conflicting idempotency reuse raises the typed domain error" do
    propose(content: "Original observation")

    assert_raises(Agent::KnowledgeSubmission::IdempotencyConflict) do
      propose(content: "Changed observation")
    end
  end

  test "subjectless requests remain valid while unknown polymorphic subjects fail closed" do
    request = Agent::PermissionRequest.create!(
      household: @grant.household,
      person: @grant.person,
      conversation: @grant.conversation,
      agent_session: @session,
      external_request_id: "subjectless-request",
      tool_name: "ordinary.permission",
      capability: "health.read",
      input_body: "{}",
      input_digest: Digest::SHA256.hexdigest("{}")
    )
    assert_nil request.permission_subject

    invalid = request.dup
    invalid.external_request_id = "unknown-subject"
    invalid.permission_subject_type = "Household"
    invalid.permission_subject_id = households(:home).id
    assert_not invalid.valid?
    assert_includes invalid.errors[:permission_subject_type], "is not included in the list"
  end

  private
    def propose(content: "A household-safe observation", request_id: "knowledge-request-1", deadline_at: 1.minute.from_now)
      Agent::KnowledgeSubmission.propose!(
        grant: @grant,
        message: @message,
        content: content,
        requested_intent: "capture",
        request_id: request_id,
        deadline_at: deadline_at
      )
    end
end
