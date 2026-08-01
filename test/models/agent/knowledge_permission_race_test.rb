require "test_helper"

class Agent::KnowledgePermissionRaceTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  test "approval racing expiry has one terminal outcome and never dispatches after expiry" do
    grant = agent_grants(:active)
    submission = Agent::KnowledgeSubmission.propose!(
      grant: grant,
      message: agent_messages(:prompt),
      content: "Race-safe household observation",
      requested_intent: "capture",
      request_id: "knowledge-race-#{SecureRandom.hex(4)}",
      deadline_at: 1.minute.from_now
    )
    request = submission.permission_request
    calls = Queue.new
    fake = Object.new
    fake.define_singleton_method(:submit) do |**_arguments|
      calls << true
      { "submission_id" => "submission_v1_race", "state" => "materialized", "updated_at" => 1 }
    end
    ready = Queue.new
    start = Queue.new
    errors = Queue.new

    with_stubbed_method(Lorester::Client, :new, fake) do
      threads = [
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            ready << true
            start.pop
            Agent::PermissionRequest.find(request.id).decide!(outcome: "approved", by: users(:two))
          rescue ActiveRecord::ActiveRecordError => error
            errors << error
          end
        end,
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            ready << true
            start.pop
            Agent::PermissionRequest.find(request.id).expire!
          rescue ActiveRecord::ActiveRecordError => error
            errors << error
          end
        end
      ]
      2.times { ready.pop }
      2.times { start << true }
      threads.each(&:join)
    end

    request.reload
    assert_includes %w[approved expired], request.status
    assert_equal(request.status == "approved" ? 1 : 0, request.decision.present? ? 1 : 0)
    assert_equal(request.status == "approved" ? 1 : 0, calls.size)
    assert_equal(request.status == "approved" ? "materialized" : "pending", submission.reload.status)
    assert_operator errors.size, :<=, 1
  ensure
    if submission
      Agent::AuditEvent.where(subject_type: "Agent::KnowledgeSubmission", subject_id: submission.id).delete_all
      Agent::AuditEvent.where(subject_type: "Agent::PermissionRequest", subject_id: request&.id).delete_all
      request&.decision&.delete
      request&.delete
      submission.delete
    end
  end
end
