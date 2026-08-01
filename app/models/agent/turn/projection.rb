require "digest"

class Agent::Turn::Projection
  SOURCE_KINDS = Agent::Message::SOURCE_KINDS.index_with(&:itself).freeze
  TOOL_STATUSES = {
    "pending" => "pending",
    "in_progress" => "running",
    "running" => "running",
    "completed" => "succeeded",
    "succeeded" => "succeeded",
    "failed" => "failed",
    "cancelled" => "cancelled"
  }.freeze

  def initialize(turn)
    @turn = turn
    @conversation = turn.conversation
    @agent_session = turn.agent_session
    @message_buffers = {}
    @tool_buffers = {}
  end

  def apply!(event)
    return unless event["method"] == "session/update"
    return unless event.dig("params", "sessionId") == @agent_session.external_session_id

    update = event.dig("params", "update").to_h
    kind = update["sessionUpdate"]
    case kind
    when "agent_message_chunk" then buffer_message!(update)
    when "tool_call", "tool_call_update" then buffer_tool!(update)
    when "plan" then project_safely(kind) { replace_plan!(update) }
    when "citation" then project_safely(kind) { upsert_citation!(update) }
    end
  end

  def flush!
    buffers = @message_buffers
    @message_buffers = {}
    buffers.each do |external_id, buffer|
      project_safely("agent_message_chunk") { append_message!(external_id, buffer) }
    end
    tools = @tool_buffers
    @tool_buffers = {}
    tools.each_value { |update| project_safely("tool_call") { upsert_tool!(update) } }
  end

  private
    def buffer_message!(update)
      text = update.dig("content", "text").to_s
      return if text.empty?

      external_id = update["messageId"].presence || "turn-#{@turn.id}-agent"
      hearth_metadata = update.dig("_meta", "hearth")
      buffer = @message_buffers[external_id] ||= {
        text: +"",
        source_kind: normalized_source_kind(hearth_metadata&.fetch("sourceKind", nil)),
        provenance: bounded_provenance(hearth_metadata),
        citations: []
      }
      buffer[:text] << text
      buffer[:source_kind] = normalized_source_kind(hearth_metadata["sourceKind"]) if hearth_metadata&.key?("sourceKind")
      buffer[:citations].concat(Array(update.dig("_meta", "citations")))
    end

    def append_message!(external_id, buffer)
      message = @conversation.messages.find_by(agent_session: @agent_session, external_id: external_id)
      if message
        body = message.body.to_s + buffer[:text]
        message.update!(body: body, body_digest: Digest::SHA256.hexdigest(body), source_kind: buffer[:source_kind])
      else
        message = @conversation.messages.create!(
          household: @turn.household,
          person: @turn.person,
          agent_session: @agent_session,
          external_id: external_id,
          role: "agent",
          body: buffer[:text],
          body_digest: Digest::SHA256.hexdigest(buffer[:text]),
          source_kind: buffer[:source_kind],
          provenance: buffer[:provenance]
        )
      end
      buffer[:citations].each { |citation| upsert_citation!(citation.merge("messageId" => external_id)) }
      message
    end

    def upsert_tool!(update)
      external_id = update["toolCallId"].presence || update["id"].presence
      return unless external_id

      activity = @conversation.tool_activities.find_or_initialize_by(agent_session: @agent_session, external_id: external_id)
      input_digest = if update.key?("rawInput")
        Digest::SHA256.hexdigest(JSON.generate(update["rawInput"] || {}))
      else
        activity.input_digest || Digest::SHA256.hexdigest("{}")
      end
      status = TOOL_STATUSES.fetch(update["status"].to_s, activity.status.presence || "running")
      activity.assign_attributes(
        household: @turn.household,
        person: @turn.person,
        source: "acp",
        tool_name: nil,
        capability: "acp.tool",
        display_title: update["title"].to_s.first(160).presence || activity.display_title || "Agent activity",
        kind: update["kind"].to_s.first(80).presence || activity.kind || "tool",
        status: status,
        input_body: nil,
        input_digest: input_digest,
        redacted_at: activity.redacted_at || Time.current,
        redaction_reason: "ACP tool input is digest-only",
        started_at: activity.started_at || Time.current
      )
      activity.completed_at ||= Time.current if activity.status.in?(%w[ succeeded failed cancelled ])
      activity.save!
    end

    def buffer_tool!(update)
      external_id = update["toolCallId"].presence || update["id"].presence
      return unless external_id

      @tool_buffers[external_id] = @tool_buffers.fetch(external_id, {}).merge(update)
    end

    def replace_plan!(update)
      entries = Array(update["entries"] || update["items"]).map do |entry|
        entry.to_h.stringify_keys.slice("content", "priority", "status")
      end.first(100)
      plan = @conversation.plan || @conversation.build_plan
      plan.update!(
        household: @turn.household,
        person: @turn.person,
        agent_session: @agent_session,
        entries: entries
      )
    end

    def upsert_citation!(update)
      value = update["citation"].presence || update
      external_id = value["id"].presence || value["externalId"].presence
      title = value["title"].to_s.first(240).presence
      return unless external_id && title

      message = if value["messageId"].present?
        @conversation.messages.find_by(agent_session: @agent_session, external_id: value["messageId"])
      end
      citation = @conversation.citations.find_or_initialize_by(agent_session: @agent_session, external_id: external_id)
      citation.update!(
        household: @turn.household,
        person: @turn.person,
        message: message,
        title: title,
        url: value["url"].presence,
        source_kind: normalized_source_kind(value["sourceKind"])
      )
    end

    def normalized_source_kind(value)
      SOURCE_KINDS.fetch(value.to_s, "agent_suggestion")
    end

    def bounded_provenance(value)
      value.to_h.stringify_keys.slice("source", "sourceId", "retrievedAt")
    end

    def project_safely(kind)
      yield
    rescue ActiveRecord::RecordInvalid, JSON::GeneratorError
      @turn.record_warning!("Ignored a malformed ACP #{kind.to_s.humanize.downcase} update.")
      nil
    end
end
