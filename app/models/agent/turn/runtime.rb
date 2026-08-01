class Agent::Turn::Runtime
  POLL_INTERVAL = 0.1
  HEARTBEAT_INTERVAL = 2.seconds

  def initialize(supervisor:, owner:, stopping: -> { false })
    @supervisor = supervisor
    @owner = owner
    @stopping = stopping
  end

  def run_next
    turn = Agent::Turn.claim_next!(owner: @owner)
    return unless turn

    run(turn)
  end

  def run(turn)
    agent_session = session_for(turn)
    turn.attach!(agent_session) unless turn.agent_session_id == agent_session.id
    connection = @supervisor.connection_for(agent_session)
    projection = Agent::Turn::Projection.new(turn.reload)
    result = Queue.new
    turn.dispatch!
    prompt_thread = Thread.new do
      Thread.current.report_on_exception = false
      result << [ :ok, @supervisor.prompt(agent_session, [ { type: "text", text: turn.user_message.body } ]) ]
    rescue StandardError => error
      result << [ :error, error ]
    end

    next_heartbeat = Time.current + HEARTBEAT_INTERVAL
    until result.length.positive?
      event = connection.poll_event(timeout: POLL_INTERVAL)
      projection.apply!(event) if event
      turn.reload
      if turn.cancellation_requested? && !turn.cancel_sent_at?
        @supervisor.cancel(agent_session)
        turn.mark_cancel_sent!
      end
      if @stopping.call && !turn.cancellation_requested?
        turn.request_cancel!
      end
      if Time.current >= next_heartbeat
        turn.heartbeat!
        next_heartbeat = Time.current + HEARTBEAT_INTERVAL
      end
    end
    while (event = connection.poll_event(timeout: 0))
      projection.apply!(event)
    end
    outcome, value = result.pop
    outcome == :ok ? turn.succeed!(stop_reason: value&.fetch("stopReason", nil)) : turn.fail!(value)
  rescue StandardError => error
    turn&.fail!(error) unless turn&.terminal?
    turn
  ensure
    prompt_thread&.join(1)
  end

  private
    def session_for(turn)
      existing = turn.conversation.sessions.where(browser_session: turn.browser_session).order(created_at: :desc).first
      return existing if existing && attached?(existing)
      return @supervisor.recover_session(existing) if existing&.external_session_id.present?

      @supervisor.start_session(conversation: turn.conversation, browser_session: turn.browser_session)
    end

    def attached?(agent_session)
      @supervisor.connection_for(agent_session)
      true
    rescue Acp::Supervisor::Error
      false
    end
end
