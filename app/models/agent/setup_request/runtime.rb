class Agent::SetupRequest::Runtime
  def initialize(instance:, supervisor:, owner:)
    @instance = instance
    @supervisor = supervisor
    @owner = owner
  end

  def run_next
    request = Agent::SetupRequest.claim_next!(owner: @owner)
    run(request) if request
  end

  def run(request)
    request.dispatch!
    candidate = Agent::Profile::Certified.fetch(request.certified_key)
    case request.action
    when "detect"
      detect(request, candidate)
    when "enable"
      with_probe(request, candidate) { |probe| candidate.observe_probe!(household: request.household, probe: probe) }
    when "authenticate", "reauthenticate"
      request.household.agent_profiles.find_by!(certified_key: request.certified_key, enabled: true)
      with_probe(request, candidate) do |probe|
        candidate.authenticate_probe!(household: request.household, probe: probe,
          method_id: request.authentication_method_id,
          origin: request.origin == "web" ? "web_setting" : "operator_command")
      end
    when "disable"
      profile = request.household.agent_profiles.find_by!(certified_key: request.certified_key)
      profile.update!(enabled: false)
      @supervisor.tick
      profile.disable_runtime_access!
      request.succeed!
    end
    request
  rescue Acp::Connection::ConfigurationError
    request&.fail!("adapter_unavailable")
  rescue Acp::Connection::TimeoutError, Timeout::Error
    request&.fail!("timeout")
  rescue Acp::Connection::Error
    request&.fail!("authentication_failed")
  rescue ActiveRecord::RecordNotFound, ActiveRecord::RecordInvalid, ArgumentError
    request&.fail!("invalid_request")
  rescue StandardError
    request&.fail!("runtime_error")
  end

  private
    def detect(request, candidate)
      cli_version = candidate.cli_version
      unless candidate.transport_available?
        return request.succeed!(cli_available: candidate.cli_available?, cli_version: cli_version,
          adapter_available: false, adapter_version: nil)
      end

      with_probe(request, candidate, cli_version: cli_version) { |_probe| }
    end

    def with_probe(request, candidate, cli_version: nil)
      candidate.with_probe(instance: @instance) do |probe|
        yield probe
        request.succeed!(cli_available: candidate.cli_available?,
          cli_version: cli_version || candidate.cli_version,
          adapter_available: true, adapter_version: probe.version)
      end
    end
end
