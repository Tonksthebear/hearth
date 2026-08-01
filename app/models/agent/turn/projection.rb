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
  end

  def apply!(event)
    return unless event["method"] == "session/update"
    return unless event.dig("params", "sessionId") == @agent_session.external_session_id

    update = event.dig("params", "update").to_h
    case update["sessionUpdate"]
    when "agent_message_chunk" then append_message!(update)
    when "tool_call" then upsert_tool!(update)
    when "tool_call_update" then update_tool!(update)
    when "plan" then replace_plan!(update)
    when "citation" then upsert_citation!(update)
    end
  end

  private
    def append_message!(update)
      text = update.dig("content", "text").to_s
      return if text.empty?

      external_id = update["messageId"].presence || "turn-#{@turn.id}-agent"
      message = @conversation.messages.find_by(agent_session: @agent_session, external_id: external_id)
      source_kind = normalized_source_kind(update.dig("_meta", "hearth", "sourceKind"))
      if message
        body = message.body.to_s + text
        message.update!(body: body, body_digest: Digest::SHA256.hexdigest(body), source_kind: source_kind)
      else
        message = @conversation.messages.create!(
          household: @turn.household,
          person: @turn.person,
          agent_session: @agent_session,
          external_id: external_id,
          role: "agent",
          body: text,
          body_digest: Digest::SHA256.hexdigest(text),
          source_kind: source_kind,
          provenance: bounded_provenance(update.dig("_meta", "hearth"))
        )
      end
      Array(update.dig("_meta", "citations")).each { |citation| upsert_citation!(citation.merge("messageId" => external_id)) }
      message
    end

    def upsert_tool!(update)
      external_id = update["toolCallId"].presence || update["id"].presence
      return unless external_id

      input = JSON.generate(update["rawInput"] || {})
      activity = @conversation.tool_activities.find_or_initialize_by(agent_session: @agent_session, external_id: external_id)
      activity.assign_attributes(
        household: @turn.household,
        person: @turn.person,
        source: "acp",
        tool_name: nil,
        capability: "acp.tool",
        display_title: update["title"].to_s.first(160).presence || "Agent activity",
        kind: update["kind"].to_s.first(80).presence || "tool",
        status: TOOL_STATUSES.fetch(update["status"].to_s, "running"),
        input_body: nil,
        input_digest: Digest::SHA256.hexdigest(input),
        redacted_at: activity.redacted_at || Time.current,
        redaction_reason: "ACP tool input is digest-only",
        started_at: activity.started_at || Time.current
      )
      activity.completed_at ||= Time.current if activity.status.in?(%w[ succeeded failed cancelled ])
      activity.save!
    end

    def update_tool!(update)
      external_id = update["toolCallId"].presence || update["id"].presence
      activity = @conversation.tool_activities.find_by(agent_session: @agent_session, external_id: external_id)
      return upsert_tool!(update) unless activity

      status = TOOL_STATUSES.fetch(update["status"].to_s, activity.status)
      activity.update!(
        display_title: update["title"].to_s.first(160).presence || activity.display_title,
        status: status,
        completed_at: status.in?(%w[ succeeded failed cancelled ]) ? Time.current : activity.completed_at
      )
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
end
