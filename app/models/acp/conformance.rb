require "json"
require "uri"

module Acp
  class Conformance
    class Error < StandardError; end

    attr_reader :instance, :profile, :conversation

    def initialize(instance:, profile: nil, conversation: nil, live: false)
      @instance = instance.require_initialized!
      @profile = profile
      @conversation = conversation
      @live = live
    end

    def run!
      selected_profile = profile || Agent::Profile.where(enabled: true).order(:id).first
      selected_conversation = conversation || selected_profile&.conversations&.order(:id)&.first
      raise Error, "Certification needs an enabled profile with a conversation" unless selected_conversation

      supervisor = Acp::Supervisor.new(instance_root: instance.root).start!
      session = supervisor.start_session(conversation: selected_conversation)
      connection = supervisor.connection_for(session)
      result = supervisor.prompt(session, [ { type: "text", text: certification_prompt } ])
      events = connection.drain_events
      updates = events.filter_map { |event| event.dig("params", "update") }
      mcp_tool_calls = Agent::ToolActivity.where(agent_session: session).order(:id).pluck(:tool_name, :status).map do |name, status|
        { name: name, status: status }
      end
      acknowledgement_observed = message_text(updates).include?("HEARTH_ACP_CERTIFIED_OK")
      citation_observed = updates.any? { |update| update["sessionUpdate"] == "citation" }
      https_citation_observed = updates.any? { |update| https_citation?(update) }
      requested_mcp_tools = @live ? %w[get_current_context list_recipes] : []
      mcp_tools_succeeded = requested_mcp_tools.all? do |name|
        mcp_tool_calls.any? { |call| call[:name] == name && call[:status] == "succeeded" }
      end
      only_allowed_mcp_tools = !@live || mcp_tool_calls.all? { |call| requested_mcp_tools.include?(call[:name]) }
      checks = {
        session_new: session.external_session_id.present?,
        prompt_completed: result["stopReason"].present?,
        acknowledgement_observed: acknowledgement_observed,
        requested_mcp_tools_succeeded: mcp_tools_succeeded,
        only_allowed_mcp_tools: only_allowed_mcp_tools
      }
      unverified = checks.filter_map { |name, passed| name.to_s unless passed }
      if @live && !https_citation_observed
        unverified.concat(%w[public_web_search https_citation])
      end
      row = {
        evidence_schema: "hearth_acp_conformance/v1",
        outcome: unverified.empty? ? "passed" : "degraded",
        protocol_version: session.installation.protocol_version,
        agent: File.basename(selected_profile.executable_path),
        version: session.installation.agent_version,
        authenticated: session.authentication_status,
        checks: checks,
        unverified: unverified,
        update_types: updates.filter_map { |update| update["sessionUpdate"] }.uniq.sort,
        tool_kinds: updates.filter_map { |update| update["kind"] if update["sessionUpdate"] == "tool_call" }.uniq.sort,
        citation_observed: citation_observed,
        https_citation_observed: https_citation_observed,
        mcp_tool_calls: mcp_tool_calls,
        mcp_transport: connection.mcp_servers.first&.fetch("type", "stdio"),
        recovery_available: session.advertised_capabilities["loadSession"] ||
          session.advertised_capabilities.dig("sessionCapabilities", "resume") ? true : false
      }
      JSON.generate(row)
    ensure
      supervisor&.shutdown!
    end

    private
      def message_text(updates)
        updates.filter_map do |update|
          next unless update["sessionUpdate"] == "agent_message_chunk"

          content = update["content"]
          content["text"] if content.is_a?(Hash)
        end.join
      end

      def https_citation?(update)
        return false unless update["sessionUpdate"] == "citation"

        uri = URI(update["url"].to_s)
        uri.is_a?(URI::HTTPS) && uri.host.present?
      rescue URI::InvalidURIError
        false
      end

      def certification_prompt
        return "Reply with HEARTH_ACP_CERTIFIED_OK." unless @live

        <<~PROMPT
          This is a bounded certification using synthetic Hearth demo data. Use only the read-only Hearth MCP tools
          get_current_context and list_recipes. Do not call write, management, submission, shell, filesystem, or mutation tools.
          Also perform one bounded public web search for the official xAI Grok Build overview and include one HTTPS citation.
          Then reply with HEARTH_ACP_CERTIFIED_OK and a short statement of which allowed checks succeeded.
        PROMPT
      end
  end
end
