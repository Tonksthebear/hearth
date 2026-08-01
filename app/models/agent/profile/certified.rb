require "open3"
require "timeout"

class Agent::Profile::Certified
  Definition = Data.define(
    :key, :name, :cli_command, :adapter_command, :arguments, :environment_keys, :credential_store
  )
  Probe = Data.define(:definition, :executable_path, :cli_path, :version, :initialized, :connection)

  DEFINITIONS = [
    Definition.new(
      key: "grok",
      name: "Grok Build",
      cli_command: "grok",
      adapter_command: "grok",
      arguments: %w[--no-auto-update agent stdio],
      environment_keys: %w[HOME PATH XDG_CONFIG_HOME GROK_API_KEY],
      credential_store: "Grok Build's documented local credential store"
    ),
    Definition.new(
      key: "codex",
      name: "Codex ACP adapter",
      cli_command: "codex",
      adapter_command: "codex-acp",
      arguments: [],
      environment_keys: %w[HOME PATH CODEX_HOME OPENAI_API_KEY],
      credential_store: "Codex's documented local credential store"
    ),
    Definition.new(
      key: "claude",
      name: "Claude ACP wrapper",
      cli_command: "claude",
      adapter_command: "claude-agent-acp",
      arguments: [],
      environment_keys: %w[HOME PATH XDG_CONFIG_HOME ANTHROPIC_API_KEY],
      credential_store: "Claude's documented local credential store"
    )
  ].index_by(&:key).freeze

  attr_reader :definition

  def self.all
    DEFINITIONS.values.map { |definition| new(definition) }
  end

  def self.fetch(key)
    new(DEFINITIONS.fetch(key.to_s) { raise ArgumentError, "Unknown certified profile: #{key}" })
  end

  def initialize(definition)
    @definition = definition
  end

  def cli_path = resolve(definition.cli_command)
  def executable_path = resolve(definition.adapter_command)
  def cli_available? = cli_path.present?
  def transport_available? = executable_path.present?

  def detection
    {
      key: definition.key,
      name: definition.name,
      cli: cli_path,
      cli_version: version_for(cli_path),
      acp_executable: executable_path,
      acp_available: transport_available?,
      credential_store: definition.credential_store
    }
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

  def persist_authentication!(household:, probe:, method_id: nil)
    profile = household.agent_profiles.find_or_initialize_by(name: definition.name)
    profile.assign_attributes(
      executable_path: probe.executable_path,
      arguments: definition.arguments,
      environment_keys: definition.environment_keys,
      working_directory: nil,
      update_policy: "manual",
      enabled: true
    )
    profile.save!

    installation = profile.installations.find_or_initialize_by(
      household: household,
      external_id: "profile-#{profile.id}"
    )
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
    return installation if methods.empty?

    selected = probe.connection.authentication_method_id(method_id)
    raise ArgumentError, "Select one advertised authentication method" unless selected

    probe.connection.authenticate(selected)
    installation.approve_authentication!(method_id: selected)
    installation
  rescue Acp::Connection::Error
    installation&.authentication_failed!
    raise
  end

  private
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
