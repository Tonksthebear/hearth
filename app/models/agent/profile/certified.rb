require "open3"
require "timeout"

class Agent::Profile::Certified
  Definition = Data.define(
    :key, :name, :cli_command, :adapter_command, :arguments, :environment_keys, :credential_store, :guidance_url
  )
  Probe = Data.define(:definition, :executable_path, :cli_path, :version, :initialized, :connection)
  State = Data.define(:candidate, :profile, :installation, :request, :detection, :runtime_status) do
    delegate :definition, to: :candidate

    def enabled? = profile&.enabled? || false
    def authentication_methods = installation&.authentication_methods || []
    def authentication_status = installation&.authentication_status || "unknown"
    def request_status = request&.status || "not_checked"
    def runtime_online? = runtime_status&.online? || false
  end

  DEFINITIONS = [
    Definition.new(
      key: "grok",
      name: "Grok Build",
      cli_command: "grok",
      adapter_command: "grok",
      arguments: %w[--no-auto-update agent stdio],
      environment_keys: %w[
        HOME PATH XDG_CONFIG_HOME XAI_API_KEY GROK_SANDBOX GROK_MEMORY GROK_SUBAGENTS GROK_WORKFLOWS
        GROK_CURSOR_SKILLS_ENABLED GROK_CURSOR_RULES_ENABLED GROK_CURSOR_AGENTS_ENABLED
        GROK_CURSOR_MCPS_ENABLED GROK_CURSOR_HOOKS_ENABLED GROK_CURSOR_SESSIONS_ENABLED
        GROK_CLAUDE_SKILLS_ENABLED GROK_CLAUDE_RULES_ENABLED GROK_CLAUDE_AGENTS_ENABLED
        GROK_CLAUDE_MCPS_ENABLED GROK_CLAUDE_HOOKS_ENABLED GROK_CLAUDE_SESSIONS_ENABLED
        GROK_CODEX_SKILLS_ENABLED GROK_CODEX_RULES_ENABLED GROK_CODEX_AGENTS_ENABLED
        GROK_CODEX_MCPS_ENABLED GROK_CODEX_HOOKS_ENABLED GROK_CODEX_SESSIONS_ENABLED
      ],
      credential_store: "Grok Build's documented local credential store",
      guidance_url: "https://docs.x.ai/build/overview"
    ),
    Definition.new(
      key: "codex",
      name: "Codex ACP adapter",
      cli_command: "codex",
      adapter_command: "codex-acp",
      arguments: [],
      environment_keys: %w[HOME PATH CODEX_HOME OPENAI_API_KEY],
      credential_store: "Codex's documented local credential store",
      guidance_url: "https://developers.openai.com/codex"
    ),
    Definition.new(
      key: "claude",
      name: "Claude ACP wrapper",
      cli_command: "claude",
      adapter_command: "claude-agent-acp",
      arguments: [],
      environment_keys: %w[HOME PATH XDG_CONFIG_HOME ANTHROPIC_API_KEY],
      credential_store: "Claude's documented local credential store",
      guidance_url: "https://docs.anthropic.com/en/docs/claude-code"
    )
  ].index_by(&:key).freeze

  attr_reader :definition

  def self.all
    DEFINITIONS.values.map { |definition| new(definition) }
  end

  def self.fetch(key)
    new(DEFINITIONS.fetch(key.to_s) { raise ArgumentError, "Unknown certified profile: #{key}" })
  end

  def self.keys = DEFINITIONS.keys

  def initialize(definition)
    @definition = definition
  end

  def cli_path = resolve(definition.cli_command)
  def executable_path = resolve(definition.adapter_command)
  def cli_available? = cli_path.present?
  def transport_available? = executable_path.present?
  def cli_version = version_for(cli_path)

  def detection
    {
      key: definition.key,
      name: definition.name,
      cli: cli_path,
      cli_version: cli_version,
      acp_executable: executable_path,
      acp_available: transport_available?,
      credential_store: definition.credential_store
    }
  end

  def state_for(household)
    profile = household.agent_profiles.find_by(certified_key: definition.key) || legacy_profile_for(household)
    State.new(
      candidate: self,
      profile: profile,
      installation: profile&.installations&.order(last_seen_at: :desc)&.first,
      request: household.agent_setup_requests.where(certified_key: definition.key).order(created_at: :desc, id: :desc).first,
      detection: household.agent_setup_requests.where(certified_key: definition.key).where.not(adapter_available: nil).order(created_at: :desc, id: :desc).first,
      runtime_status: household.agent_runtime_status
    )
  end

  def with_probe(instance:, &block)
    raise Acp::Connection::ConfigurationError, "#{definition.name} ACP executable is unavailable" unless transport_available?

    connection = Acp::Connection.new(
      argv: [ executable_path, *definition.arguments ],
      cwd: instance.root.to_s,
      environment: ENV.slice(*definition.environment_keys),
      mcp_servers: [],
      timeout: 30
    ).start
    initialized = connection.initialize_connection
    yield Probe.new(
      definition: definition,
      executable_path: executable_path,
      cli_path: cli_path,
      version: connection.agent_info["version"] || version_for(executable_path),
      initialized: initialized,
      connection: connection
    )
  ensure
    connection&.stop
  end

  def observe_probe!(household:, probe:, enabled: true)
    profile = household.agent_profiles.find_by(certified_key: definition.key) ||
      legacy_profile_for(household) || household.agent_profiles.new(certified_key: definition.key)
    profile.assign_attributes(
      certified_key: definition.key,
      name: definition.name,
      executable_path: probe.executable_path,
      arguments: definition.arguments,
      environment_keys: definition.environment_keys,
      working_directory: nil,
      update_policy: "manual",
      enabled: enabled
    )
    profile.save!

    installation = profile.installations.find_or_initialize_by(household: household, external_id: "profile-#{profile.id}")
    installation.executable_path = probe.executable_path
    installation.protocol_version ||= probe.initialized.fetch("protocolVersion")
    installation.save! if installation.new_record?
    methods = probe.connection.auth_methods.map { |method| method.slice("id", "name") }
    installation.observe!(
      protocol_version: probe.initialized.fetch("protocolVersion"),
      capabilities: probe.connection.agent_capabilities,
      authentication_methods: methods,
      authentication_status: methods.empty? ? "not_required" : "required",
      agent_version: probe.connection.agent_info["version"] || probe.version
    )
    installation.require_authentication! if methods.any?
    installation
  end

  def authenticate_probe!(household:, probe:, method_id:, origin:)
    installation = observe_probe!(household: household, probe: probe)
    selected = probe.connection.authentication_method_id(method_id)
    raise ArgumentError, "Select one advertised authentication method" unless selected

    probe.connection.authenticate(selected)
    installation.approve_authentication!(method_id: selected, origin: origin)
    installation
  rescue Acp::Connection::Error
    installation&.authentication_failed!
    raise
  end

  private
    def legacy_profile_for(household)
      household.agent_profiles.find_by(certified_key: nil, name: definition.name)
    end

    def resolve(command)
      return File.expand_path(command) if command.include?(File::SEPARATOR) && File.executable?(command)

      ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).filter_map do |directory|
        candidate = File.join(directory, command)
        File.expand_path(candidate) if File.file?(candidate) && File.executable?(candidate)
      end.first
    end

    def version_for(path)
      return unless path

      Timeout.timeout(5) do
        stdout, stderr, status = Open3.capture3(path, "--version", unsetenv_others: false)
        value = [ stdout, stderr ].find(&:present?).to_s.lines.first.to_s.strip
        status.success? && value.present? ? value[0, 200] : nil
      end
    rescue SystemCallError, Timeout::Error
      nil
    end
end
