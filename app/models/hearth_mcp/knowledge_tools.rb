require "mcp"

module HearthMcp
  module KnowledgeTools
    CAPABILITIES = %w[knowledge.read knowledge.submit].freeze
    ERROR_CODES = %w[
      not_configured stopped unavailable stale incompatible not_found pressure in_progress
      idempotency_conflict authorization validation failed
    ].freeze
    EMPTY_OBJECT = { type: "object", maxProperties: 0 }.freeze
    PROVENANCE_SCHEMA = {
      type: "object",
      properties: {
        contract_version: { type: "integer", const: Lorester::Client::CONTRACT_VERSION },
        source_commit: { type: [ "string", "null" ] },
        submission_id: { type: [ "string", "null" ] },
        state: { type: [ "string", "null" ] },
        truncated: { type: [ "boolean", "null" ] }
      },
      required: %w[contract_version source_commit submission_id state truncated],
      additionalProperties: false
    }.freeze
    BOUNDED_TEXT_SCHEMA = {
      type: "object",
      properties: { text: { type: "string" }, truncated: { type: "boolean" } },
      required: %w[text truncated],
      additionalProperties: false
    }.freeze
    CITATION_SCHEMA = {
      type: "object",
      properties: {
        source_commit: { type: "string" },
        contract_version: { type: "integer", const: Lorester::Client::CONTRACT_VERSION }
      },
      required: %w[source_commit contract_version],
      additionalProperties: false
    }.freeze
    NOTE_SCHEMA = {
      type: "object",
      properties: {
        id: { type: "string" },
        title: BOUNDED_TEXT_SCHEMA,
        description: { oneOf: [ BOUNDED_TEXT_SCHEMA, { type: "null" } ] },
        excerpt: BOUNDED_TEXT_SCHEMA,
        citation: CITATION_SCHEMA
      },
      required: %w[id title description excerpt citation],
      additionalProperties: false
    }.freeze
    NOTES_SCHEMA = {
      type: "object",
      properties: {
        notes: { type: "array", maxItems: 20, items: NOTE_SCHEMA },
        truncated: { type: "boolean" }
      },
      required: %w[notes truncated],
      additionalProperties: false
    }.freeze
    DISCOVERY_SCHEMA = {
      type: "object",
      properties: {
        contract_version: { type: "integer", const: Lorester::Client::CONTRACT_VERSION },
        control_protocol_version: { type: "integer" },
        owner_started_at: { type: "integer" },
        readiness: { type: "string", enum: %w[ready unavailable stale incompatible] },
        source_commit: { type: [ "string", "null" ] }
      },
      required: %w[contract_version control_protocol_version owner_started_at readiness source_commit],
      additionalProperties: false
    }.freeze
    SUBMISSION_SCHEMA = {
      type: "object",
      properties: {
        submission_id: { type: [ "integer", "string", "null" ] },
        status: { type: "string" },
        deadline_at: { type: [ "string", "null" ] },
        next_action: { type: [ "string", "null" ] },
        lorester_submission_id: { type: [ "string", "null" ] },
        diagnostic: { type: [ "string", "null" ] },
        updated_at: { type: [ "integer", "null" ] }
      },
      required: %w[submission_id status deadline_at next_action lorester_submission_id diagnostic updated_at],
      additionalProperties: false
    }.freeze

    class Base < MCP::Tool
      class << self
        attr_reader :capability

        def knowledge_contract(name:, description:, capability:, properties:, required:, result_schema:, read_only: true)
          @capability = capability
          tool_name name
          self.description description
          input_schema(type: "object", properties: properties, required: required, additionalProperties: false)
          output_schema(
            oneOf: [
              {
                type: "object",
                properties: {
                  status: { type: "string", const: "ok" },
                  result: result_schema,
                  provenance: PROVENANCE_SCHEMA
                },
                required: %w[status result provenance],
                additionalProperties: false
              },
              {
                type: "object",
                properties: {
                  status: { type: "string", enum: ERROR_CODES },
                  result: EMPTY_OBJECT,
                  provenance: PROVENANCE_SCHEMA
                },
                required: %w[status result provenance],
                additionalProperties: false
              }
            ]
          )
          annotations(read_only_hint: read_only, destructive_hint: false, idempotent_hint: true, open_world_hint: false)
        end

        def perform(server_context:)
          grant = server_context.fetch(:grant)
          return error_response("failed", grant: grant) unless grant.consume(calls: 1) == 1

          result = yield(grant)
          response(result, grant: grant)
        rescue Lorester::Client::Error => error
          error_response(error.code, grant: grant)
        rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotFound, ArgumentError => error
          error_response("validation", grant: grant)
        end

        def response(result, grant:)
          payload = { status: "ok", result: result, provenance: provenance_for(result) }
          json = JSON.generate(payload)
          tokens = (json.bytesize / 4.0).ceil
          return error_response("failed", grant: grant) unless grant.consume(calls: 0, output_tokens: tokens) == 1

          MCP::Tool::Response.new([ { type: "text", text: json } ], structured_content: payload)
        end

        def error_response(code, grant:)
          payload = { status: ERROR_CODES.include?(code) ? code : "failed", result: {}, provenance: empty_provenance }
          MCP::Tool::Response.new(
            [ { type: "text", text: JSON.generate(payload) } ],
            structured_content: payload,
            error: true
          )
        end

        def client = Lorester::Client.new

        private
          def provenance_for(result)
            notes = result["notes"] || (result["citation"] ? [ result ] : [])
            source_commit = result["source_commit"] || notes.first&.dig("citation", "source_commit")
            {
              contract_version: Lorester::Client::CONTRACT_VERSION,
              source_commit: source_commit,
              submission_id: result["lorester_submission_id"],
              state: result["status"] || result["readiness"],
              truncated: result["truncated"]
            }
          end

          def empty_provenance
            {
              contract_version: Lorester::Client::CONTRACT_VERSION,
              source_commit: nil,
              submission_id: nil,
              state: nil,
              truncated: nil
            }
          end
      end
    end

    class Search < Base
      knowledge_contract name: "knowledge.search",
        description: "Search Lorester's current bounded knowledge projection without exposing vault paths.",
        capability: "knowledge.read",
        properties: { query: { type: "string", minLength: 1, maxLength: 512 } },
        required: %w[query],
        result_schema: NOTES_SCHEMA

      def self.call(query:, server_context:)
        perform(server_context: server_context) { client.search(query) }
      end
    end

    class NoteRead < Base
      knowledge_contract name: "knowledge.note.read",
        description: "Read one bounded Lorester note by opaque identity with exact citation provenance.",
        capability: "knowledge.read",
        properties: { note_id: { type: "string", minLength: 1, maxLength: 128 } },
        required: %w[note_id],
        result_schema: NOTE_SCHEMA

      def self.call(note_id:, server_context:)
        perform(server_context: server_context) { client.read(note_id) }
      end
    end

    class Related < Base
      knowledge_contract name: "knowledge.related",
        description: "Return bounded Lorester related notes by opaque identity with citations.",
        capability: "knowledge.read",
        properties: { note_id: { type: "string", minLength: 1, maxLength: 128 } },
        required: %w[note_id],
        result_schema: NOTES_SCHEMA

      def self.call(note_id:, server_context:)
        perform(server_context: server_context) { client.related(note_id) }
      end
    end

    class HealthSummary < Base
      knowledge_contract name: "knowledge.health.summary",
        description: "Return Lorester owner compatibility and projection readiness without filesystem details.",
        capability: "knowledge.read",
        properties: {},
        required: [],
        result_schema: DISCOVERY_SCHEMA

      def self.call(server_context:)
        perform(server_context: server_context) { client.discover }
      end
    end

    class InboxSubmit < Base
      knowledge_contract name: "knowledge.inbox.submit",
        description: "Stage household-safe redacted conversation content for required Hearth confirmation before Lorester materialization.",
        capability: "knowledge.submit",
        properties: {
          message_id: { type: "integer", minimum: 1 },
          content: { type: "string", minLength: 1, maxLength: 65_536 },
          requested_intent: { type: "string", minLength: 1, maxLength: 64 },
          idempotency_key: { type: "string", minLength: 8, maxLength: 128 }
        },
        required: %w[message_id content requested_intent idempotency_key],
        result_schema: SUBMISSION_SCHEMA,
        read_only: false

      def self.call(message_id:, content:, requested_intent:, idempotency_key:, server_context:)
        perform(server_context: server_context) do |grant|
          message = grant.conversation.messages.find(message_id)
          submission = Agent::KnowledgeSubmission.propose!(
            grant: grant,
            message: message,
            content: content,
            requested_intent: requested_intent,
            request_id: idempotency_key,
            deadline_at: [ grant.expires_at, 5.minutes.from_now ].min
          )
          submission_payload(submission)
        end
      end

      def self.submission_payload(submission)
        request = submission.permission_request
        {
          "submission_id" => submission.id,
          "status" => submission.status,
          "deadline_at" => request.deadline_at&.utc&.iso8601,
          "next_action" => request.status == "pending" ? "Approve the durable Hearth knowledge submission before Lorester dispatch." : nil,
          "lorester_submission_id" => submission.lorester_submission_id,
          "diagnostic" => submission.diagnostic,
          "updated_at" => submission.provenance["updated_at"]
        }
      end
    end

    class InboxStatus < Base
      knowledge_contract name: "knowledge.inbox.status",
        description: "Return the bounded Hearth/Lorester lifecycle for one submission in this exact ACP session.",
        capability: "knowledge.read",
        properties: { submission_id: { type: "integer", minimum: 1 } },
        required: %w[submission_id],
        result_schema: SUBMISSION_SCHEMA

      def self.call(submission_id:, server_context:)
        perform(server_context: server_context) do |grant|
          submission = Agent::KnowledgeSubmission.find_by!(id: submission_id, agent_session: grant.agent_session)
          submission.refresh_status! if submission.lorester_submission_id.present?
          InboxSubmit.submission_payload(submission)
        end
      end
    end

    READ = [ Search, NoteRead, Related, InboxStatus, HealthSummary ].freeze
    SUBMIT = [ InboxSubmit ].freeze
    ALL = (READ + SUBMIT).freeze
  end
end
