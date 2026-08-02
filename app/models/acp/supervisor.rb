require "uri"

module Acp
  class Supervisor
    class Error < StandardError; end
    class RecoveryUnavailable < Error; end
    class InstallationMismatch < Error; end
    class ProfileDisabled < Error; end
    class AuthenticationRequired < Error; end

    DEFAULT_BACKOFFS = [ 0.25, 1, 4 ].freeze
    PERMISSION_RECONCILIATION_INTERVAL = 0.1

    attr_reader :recovery_methods, :runtime_directory, :session_list_observations

    def initialize(instance_root:, runtime_directory: nil, connection_factory: nil,
      recovery_backoffs: DEFAULT_BACKOFFS, on_fatal: ->(_session, _error) { },
      runtime_capability_groups: nil,
      mcp_url: ENV.fetch("HEARTH_MCP_URL", "http://127.0.0.1:3000/mcp"))
      @instance_root = File.expand_path(instance_root)
      @mcp_url = validate_mcp_url(mcp_url)
      @runtime_directory = runtime_directory || Acp::RuntimeDirectory.new(instance_root: @instance_root)
      @connection_factory = connection_factory || ->(**arguments) { Acp::Connection.new(**arguments) }
      @recovery_backoffs = recovery_backoffs.map { |value| Float(value) }.freeze
      @on_fatal = on_fatal
      @runtime_capability_groups = runtime_capability_groups
      @connections = {}
      @connections_mutex = Mutex.new
      @session_list_observations = {}
      @recovery_methods = {}
      @started = false
    end

    def start!
      return self if @started

      runtime_directory.acquire!
      @started = true
      self
    end

    def start_session(conversation:, browser_session: nil)
      ensure_started!
      ensure_profile_enabled!(conversation.profile)
      connection = build_connection(conversation.profile).start
      initialized = connection.initialize_connection
      installation = observe_installation!(conversation.profile, connection, initialized)
      authenticate!(connection, installation)
      agent_session = Agent::Session.create!(
        household: conversation.household,
        person: conversation.person,
        conversation: conversation,
        installation: installation,
        browser_session: browser_session,
        external_session_id: nil,
        status: "starting",
        advertised_capabilities: connection.agent_capabilities,
        authentication_status: installation.authentication_status,
        mcp_authorization_status: "not_configured"
      )
      configure_permission_handler(connection, agent_session)
      credential = agent_session.issue_runtime_grant!(capability_groups: @runtime_capability_groups)
      connection.configure_mcp_servers!(mcp_servers_for(connection, credential))
      result = connection.new_session
      agent_session.bind_external_session!(result.fetch("sessionId"))
      agent_session.connect!
      register(agent_session, connection)
      agent_session
    rescue => error
      agent_session&.fail_initialization!(error) if agent_session&.persisted? && agent_session.status == "starting"
      connection&.stop
      raise
    end

    def recover_session(agent_session)
      ensure_started!
      ensure_profile_enabled!(agent_session.conversation.profile)
      prepare_for_recovery!(agent_session)
      connection = build_connection(agent_session.conversation.profile).start
      initialized = connection.initialize_connection
      installation = observe_installation!(agent_session.conversation.profile, connection, initialized)
      unless installation.id == agent_session.installation_id
        raise InstallationMismatch, "Recovered ACP agent does not match the persisted installation"
      end

      authenticate!(connection, installation)
      agent_session.begin_recovery!
      configure_permission_handler(connection, agent_session)
      credential = agent_session.issue_runtime_grant!(capability_groups: @runtime_capability_groups)
      connection.configure_mcp_servers!(mcp_servers_for(connection, credential))
      observe_session_list(agent_session, connection)
      @recovery_methods[agent_session.id] = restore_session(connection, agent_session.external_session_id)
      agent_session.reload.connect!
      register(agent_session, connection)
      agent_session
    rescue Acp::Connection::ProcessError,
      Acp::Connection::TimeoutError,
      Acp::Connection::BackpressureError => error
      connection&.stop
      schedule_retry(agent_session, error)
    rescue Acp::Connection::Error, Error, ActiveRecord::ActiveRecordError => error
      connection&.stop
      terminal_recovery_failure(agent_session, error)
    rescue StandardError => error
      connection&.stop
      terminal_recovery_failure(agent_session, error)
    end

    def prompt(agent_session, content)
      connection_for(agent_session).prompt(content)
    end

    def cancel(agent_session)
      connection_for(agent_session).cancel
    end

    def events_for(agent_session)
      connection_for(agent_session).drain_events
    end

    def connection_for(agent_session)
      @connections_mutex.synchronize { @connections[agent_session.id] } ||
        raise(Error, "ACP session #{agent_session.id} is not attached to this runtime")
    end

    def tick
      ensure_started!
      disconnect_disabled_profiles
      reap_failed_connections
      expire_operational_authorizations
      rotate_stale_authorizations
      expire_pending_mutations
      attached_ids = @connections_mutex.synchronize { @connections.keys }
      Agent::Session.recoverable
        .joins(conversation: :profile)
        .where(agent_profiles: { enabled: true })
        .where.not(id: attached_ids)
        .find_each { |agent_session| recover_session(agent_session) }
      self
    end

    def shutdown!
      connections = @connections_mutex.synchronize do
        owned = @connections
        @connections = {}
        owned
      end
      connections.each do |session_id, connection|
        connection.stop
        agent_session = Agent::Session.find_by(id: session_id)
        if agent_session&.status.in?(%w[ starting connected ])
          agent_session.disconnect!(reason: "ACP runtime stopped")
        end
      end
      runtime_directory.release!
      @started = false
      nil
    end

    private
      def ensure_started!
        raise Error, "ACP supervisor has not acquired its runtime directory" unless @started
      end

      def ensure_profile_enabled!(profile)
        raise ProfileDisabled, "Agent profile is disabled" unless profile.enabled?
      end

      def disconnect_disabled_profiles
        disabled_ids = Agent::Session
          .joins(conversation: :profile)
          .where(id: @connections_mutex.synchronize { @connections.keys })
          .where(agent_profiles: { enabled: false })
          .pluck(:id)
        disabled = @connections_mutex.synchronize do
          disabled_ids.to_h { |session_id| [ session_id, @connections.delete(session_id) ] }
        end
        disabled.each do |session_id, connection|
          connection&.stop
          agent_session = Agent::Session.find_by(id: session_id)
          if agent_session&.status.in?(%w[ starting connected ])
            agent_session.disconnect!(
              reason: "Agent profile disabled",
              recovery_error: "Agent profile is disabled"
            )
          end
        end
      end

      def build_connection(profile)
        @connection_factory.call(
          argv: profile.argv,
          cwd: profile.working_directory_for(@instance_root),
          environment: profile.environment_from,
          mcp_servers: []
        )
      end

      def configure_permission_handler(connection, agent_session)
        connection.configure_permission_handler! do |params|
          resolve_permission(agent_session, params)
        end
      end

      def resolve_permission(agent_session, params)
        return permission_rejection(params, code: "context_mismatch", message: "ACP session does not match the staged Hearth session") unless params["sessionId"] == agent_session.external_session_id
        tool_call_id = params.dig("toolCall", "toolCallId")
        return permission_rejection(params, code: "missing_tool_call", message: "toolCallId is required") if tool_call_id.blank?
        operation = params.dig("toolCall", "title")
        return permission_rejection(params, code: "stage_required", message: "Call the typed Hearth MCP tool first to stage this operation") if operation.blank?
        raw_input = params.dig("toolCall", "rawInput")
        return permission_rejection(params, code: "stage_required", message: "Call the typed Hearth MCP tool first with complete typed input") unless raw_input.is_a?(Hash)
        idempotency_key = raw_input["idempotency_key"]
        return permission_rejection(params, code: "stage_required", message: "Stage the typed MCP proposal before requesting permission with its idempotency_key") if idempotency_key.blank?

        proposal = agent_session.mutation_proposals.find_by(idempotency_key: idempotency_key)
        return permission_rejection(params, code: "stage_required", message: "No staged Hearth proposal matches this idempotency_key") unless proposal
        unless valid_permission_correlation?(proposal, agent_session, operation, raw_input)
          return permission_rejection(params, code: "correlation_mismatch", message: "The staged proposal does not match this exact operation, input, grant, deadline, and context")
        end

        request = proposal.permission_request
        request.update!(external_request_id: tool_call_id) if request.external_request_id.start_with?("mutation-")
        deadline = [ proposal.deadline_at, Acp::Connection::DEFAULT_TIMEOUT.seconds.from_now ].min
        wait_for_permission_decision(proposal, deadline)
        proposal.cancel!(reason: "ACP permission wait ended", status: "expired") if proposal.status == "pending"

        kind = proposal.status.in?(%w[ approved executed ]) ? "allow_once" : "reject_once"
        option = params["options"]&.find { |candidate| candidate["kind"] == kind }
        permission_selection(option, code: "proposal_#{proposal.status}", message: "Hearth proposal #{proposal.status}")
      end

      def valid_permission_correlation?(proposal, agent_session, operation, raw_input)
        grant = proposal.agent_grant
        proposal.status == "pending" && proposal.deadline_at > Time.current &&
          proposal.operation == operation &&
          proposal.input_digest == Agent::MutationProposal.input_digest_for(raw_input.except("idempotency_key")) &&
          proposal.household_id == agent_session.household_id && proposal.person_id == agent_session.person_id &&
          proposal.conversation_id == agent_session.conversation_id &&
          grant.agent_session_id == agent_session.id && grant.revoked_at.nil? && grant.expires_at > Time.current &&
          grant.allows_capability?("health.write")
      end

      def wait_for_permission_decision(proposal, deadline)
        decision = Queue.new
        subscribed = Queue.new
        callback = ->(_payload) { decision.push(true) }
        ActionCable.server.pubsub.subscribe(proposal.permission_channel, callback, -> { subscribed.push(true) })
        remaining = [ deadline - Time.current, 0 ].max
        subscribed.pop(timeout: [ remaining, 2 ].min) if remaining.positive?
        loop do
          proposal.reload
          break unless proposal.status == "pending"

          remaining = deadline - Time.current
          break unless remaining.positive?

          decision.pop(timeout: [ remaining, PERMISSION_RECONCILIATION_INTERVAL ].min)
        end
        proposal.reload.expire_if_needed! if proposal.status == "pending"
      ensure
        ActionCable.server.pubsub.unsubscribe(proposal.permission_channel, callback) if callback
      end

      def permission_rejection(params, code: "permission_rejected", message: "Hearth rejected this permission request")
        option = params["options"]&.find { |candidate| candidate["kind"] == "reject_once" }
        permission_selection(option, code: code, message: message)
      end

      def permission_selection(option, code:, message:)
        {
          outcome: option ? { outcome: "selected", optionId: option.fetch("optionId") } : { outcome: "cancelled" },
          _meta: { hearth: { code: code, message: message } }
        }
      end

      def rotate_stale_authorizations
        stale_ids = Agent::Session.where(
          id: @connections_mutex.synchronize { @connections.keys },
          mcp_authorization_status: "reauthorization_required"
        ).pluck(:id)
        detached = @connections_mutex.synchronize do
          stale_ids.to_h { |session_id| [ session_id, @connections.delete(session_id) ] }
        end
        detached.each do |session_id, connection|
          connection.stop
          Agent::Session.find(session_id).detach_for_authorization_rotation!
        end
      end

      def expire_operational_authorizations
        Agent::OperationalAuthorization.where(revoked_at: nil).where(expires_at: ..Time.current).find_each do |authorization|
          authorization.revoke!(reason: "operational access expired")
        end
      end

      def expire_pending_mutations
        Agent::MutationProposal.pending.where(deadline_at: ..Time.current).find_each(&:expire_if_needed!)
        Agent::PermissionRequest.where(status: "pending", deadline_at: ..Time.current).find_each(&:expire_if_needed!)
      end

      def mcp_servers_for(connection, credential)
        if connection.agent_capabilities.dig("mcpCapabilities", "http")
          [
            {
              name: "Hearth",
              type: "http",
              url: @mcp_url,
              headers: [ { name: "Authorization", value: "Bearer #{credential.bearer}" } ]
            }
          ]
        else
          [
            {
              name: "Hearth",
              command: Rails.root.join("bin/hearth-mcp-proxy").to_s,
              args: [],
              env: [
                { name: "HEARTH_MCP_URL", value: @mcp_url },
                { name: "HEARTH_MCP_BEARER", value: credential.bearer }
              ]
            }
          ]
        end
      end

      def validate_mcp_url(value)
        uri = URI(value)
        unless uri.is_a?(URI::HTTP) && %w[127.0.0.1 ::1 localhost].include?(uri.host)
          raise ArgumentError, "Hearth MCP URL must use loopback HTTP"
        end

        uri.to_s
      rescue URI::InvalidURIError
        raise ArgumentError, "Hearth MCP URL must use loopback HTTP"
      end

      def observe_installation!(profile, connection, initialized)
        info = connection.agent_info
        installation = profile.installations.find_or_initialize_by(
          household: profile.household,
          external_id: "profile-#{profile.id}"
        )
        installation.executable_path ||= profile.executable_path
        installation.protocol_version ||= initialized.fetch("protocolVersion")
        installation.save! if installation.new_record?
        methods = connection.auth_methods.map { |method| method.slice("id", "name") }
        approved_method = installation.authentication_method_id
        approved = approved_method.present? && methods.any? { |method| method["id"] == approved_method }
        status = if methods.empty?
          "not_required"
        elsif approved
          installation.authentication_status
        else
          "required"
        end
        installation.observe!(
          protocol_version: initialized.fetch("protocolVersion"),
          capabilities: connection.agent_capabilities,
          authentication_methods: methods,
          authentication_status: status,
          agent_version: info["version"]
        )
        installation
      end

      def authenticate!(connection, installation)
        return if installation.authentication_status == "not_required"

        method_id = installation.approved_authentication_method
        unless method_id
          installation.require_authentication!
          raise AuthenticationRequired, "Agent authentication setup is required; run `bin/hearth agent setup`"
        end

        connection.authenticate(connection.authentication_method_id(method_id))
        installation.update!(authentication_status: "authenticated")
      rescue Acp::Connection::Error
        installation.authentication_failed!
        raise AuthenticationRequired, "Agent authentication failed; run `bin/hearth agent setup`"
      end

      def prepare_for_recovery!(agent_session)
        agent_session.reload
        if agent_session.status.in?(%w[ starting connected ])
          agent_session.disconnect!(reason: "ACP transport restarted")
        else
          agent_session.prepare_for_transport_recovery!
        end

        agent_session
      end

      def observe_session_list(agent_session, connection)
        return unless connection.agent_capabilities.dig("sessionCapabilities", "list")

        @session_list_observations[agent_session.id] = connection.list_sessions(
          cwd: agent_session.conversation.profile.working_directory_for(@instance_root)
        )
      rescue Acp::Connection::RequestError => error
        @session_list_observations[agent_session.id] = { "error" => error.message }
      end

      def restore_session(connection, session_id)
        if connection.agent_capabilities.dig("sessionCapabilities", "resume")
          begin
            connection.resume(session_id)
            return "resume"
          rescue Acp::Connection::RequestError
            raise unless connection.agent_capabilities["loadSession"]
          end
        end
        if connection.agent_capabilities["loadSession"]
          connection.load(session_id)
          return "load"
        end

        raise RecoveryUnavailable, "Agent advertises neither session/resume nor session/load"
      end

      def register(agent_session, connection)
        @connections_mutex.synchronize { @connections[agent_session.id] = connection }
      end

      def reap_failed_connections
        failures = @connections_mutex.synchronize do
          @connections.filter_map do |session_id, connection|
            next unless connection.failure

            @connections.delete(session_id)
            [ session_id, connection.failure ]
          end
        end
        failures.each do |session_id, error|
          agent_session = Agent::Session.find_by(id: session_id)
          schedule_retry(agent_session, error) if agent_session&.status.in?(%w[ starting connected disconnected ])
        end
      end

      def schedule_retry(agent_session, error)
        return unless agent_session

        attempt = agent_session.reload.recovery_attempts + 1
        if attempt > @recovery_backoffs.length
          terminal_recovery_failure(agent_session, error)
        else
          retry_at = Time.current + @recovery_backoffs.fetch(attempt - 1)
          agent_session.record_recovery_failure!(error: error.message, retry_at: retry_at)
        end
        agent_session
      end

      def terminal_recovery_failure(agent_session, error)
        return unless agent_session

        agent_session.reload.fail_recovery!(error.message)
        @on_fatal.call(agent_session, error)
        agent_session
      end
  end
end
