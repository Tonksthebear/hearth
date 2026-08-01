require "fileutils"
require "pathname"
require "securerandom"
require "yaml"

module Hearth
  class Instance
    class Error < StandardError; end
    class Uninitialized < Error; end
    class AlreadyInitialized < Error; end
    class Running < Error; end
    class UnsafeRestore < Error; end

    DIRECTORY_MODE = 0o700
    FILE_MODE = 0o600
    DATABASE_FILES = {
      "DATABASE_URL" => "production.sqlite3",
      "CACHE_DATABASE_URL" => "production_cache.sqlite3",
      "QUEUE_DATABASE_URL" => "production_queue.sqlite3",
      "CABLE_DATABASE_URL" => "production_cable.sqlite3"
    }.freeze
    DURABLE_ENTRIES = %w[instance.yml secret_key_base storage].freeze

    attr_reader :root

    def self.initialized?(root)
      new(root).initialized?
    end

    def initialize(root = Dir.pwd)
      @root = Pathname.new(root).expand_path
    end

    def hearth_root = root.join(".hearth")
    def marker_path = hearth_root.join("instance.yml")
    def secret_path = hearth_root.join("secret_key_base")
    def storage_path = hearth_root.join("storage")
    def uploads_path = storage_path.join("uploads")
    def log_path = hearth_root.join("log")
    def tmp_path = hearth_root.join("tmp")
    def acp_path = tmp_path.join("acp")
    def acp_lock_path = acp_path.join("supervisor.lock")
    def acp_pid_path = acp_path.join("supervisor.pid")
    def launcher_path = tmp_path.join("launcher")
    def launcher_lock_path = launcher_path.join("serve.lock")
    def launcher_pid_path = launcher_path.join("serve.pid")

    def initialized?
      marker_path.file?
    end

    def require_initialized!
      return self if initialized?

      raise Uninitialized, "Hearth instance is not initialized at #{root}; expected #{marker_path}. No files were written."
    end

    def initialize!
      created_hearth_root = false
      raise AlreadyInitialized, "Hearth is already initialized at #{root}" if initialized?
      raise AlreadyInitialized, "#{hearth_root} already exists" if hearth_root.exist?

      created_hearth_root = true
      FileUtils.mkdir_p([ uploads_path, log_path, acp_path, launcher_path ], mode: DIRECTORY_MODE)
      secure_directories!
      write_private(marker_path, YAML.dump("version" => 1, "instance_id" => SecureRandom.uuid))
      write_private(secret_path, "#{SecureRandom.hex(64)}\n")
      write_private(log_path.join("production.log"), "")
      write_private(log_path.join("launcher.jsonl"), "")
      self
    rescue
      FileUtils.rm_rf(hearth_root) if created_hearth_root && hearth_root.exist?
      raise
    end

    def environment(port: nil, runtime: false)
      require_initialized!
      values = {
        "RAILS_ENV" => "production",
        "SECRET_KEY_BASE" => secret_path.read.strip,
        "HEARTH_STORAGE_ROOT" => uploads_path.to_s
      }
      DATABASE_FILES.each { |name, filename| values[name] = "sqlite3:#{storage_path.join(filename)}" }
      if runtime
        values.merge!(
          "RAILS_LOG_PATH" => log_path.join("production.log").to_s,
          "HEARTH_TMP" => tmp_path.to_s,
          "TMPDIR" => tmp_path.to_s,
          "PIDFILE" => launcher_path.join("puma.pid").to_s,
          "STATE_PATH" => launcher_path.join("puma.state").to_s,
          "SOLID_QUEUE_IN_PUMA" => "true"
        )
      end
      if port
        values["PORT"] = Integer(port).to_s
        values["HEARTH_MCP_URL"] = "http://127.0.0.1:#{Integer(port)}/mcp"
      end
      values
    end

    def prepare_runtime!
      require_initialized!
      FileUtils.mkdir_p([ uploads_path, log_path, acp_path, launcher_path ], mode: DIRECTORY_MODE)
      secure_directories!
      [ log_path.join("production.log"), log_path.join("launcher.jsonl") ].each do |path|
        write_private(path, "") unless path.exist?
      end
      self
    end

    def database_paths
      DATABASE_FILES.transform_values { |filename| storage_path.join(filename) }
    end

    def ready?
      initialized? && secret_path.file? && DURABLE_ENTRIES.all? { |entry| hearth_root.join(entry).exist? }
    end

    def stopped?
      [ acp_lock_path, launcher_lock_path ].all? { |path| lock_available?(path) }
    end

    def backup!(destination)
      require_initialized!
      raise Running, "Stop Hearth before creating a backup" unless stopped?

      destination = Pathname.new(destination).expand_path
      raise Error, "Backup destination already exists: #{destination}" if destination.exist?
      DURABLE_ENTRIES.each do |entry|
        hearth_root.join(entry).find { |path| raise Error, "Backup source contains a symbolic link" if path.symlink? }
      end
      FileUtils.mkdir_p(destination.dirname, mode: DIRECTORY_MODE)
      system("tar", "-czf", destination.to_s, "-C", hearth_root.to_s, *DURABLE_ENTRIES) ||
        raise(Error, "Backup command failed")
      File.chmod(FILE_MODE, destination)
      destination
    end

    def restore!(archive)
      created_hearth_root = false
      raise UnsafeRestore, "Restore root must be empty: #{root}" if root.exist? && root.children.any?

      archive = Pathname.new(archive).expand_path
      raise UnsafeRestore, "Backup does not exist: #{archive}" unless archive.file?
      entries = IO.popen([ "tar", "-tzf", archive.to_s ], &:readlines).map(&:strip).reject(&:empty?)
      validate_archive_entries!(entries)
      created_hearth_root = true
      FileUtils.mkdir_p(hearth_root, mode: DIRECTORY_MODE)
      system("tar", "-xzf", archive.to_s, "-C", hearth_root.to_s) || raise(UnsafeRestore, "Restore command failed")
      require_initialized!
      secure_tree!
      self
    rescue
      FileUtils.rm_rf(hearth_root) if created_hearth_root && hearth_root.exist?
      raise
    end

    private
      def write_private(path, contents)
        File.open(path, File::WRONLY | File::CREAT | File::EXCL, FILE_MODE) do |file|
          file.write(contents)
          file.flush
          file.fsync
        end
        File.chmod(FILE_MODE, path)
      end

      def secure_directories!
        [ hearth_root, storage_path, uploads_path, log_path, tmp_path, acp_path, launcher_path ].each do |path|
          File.chmod(DIRECTORY_MODE, path)
        end
      end

      def secure_tree!
        hearth_root.find do |path|
          raise UnsafeRestore, "Backup contains a symbolic link" if path.symlink?
          File.chmod(path.directory? ? DIRECTORY_MODE : FILE_MODE, path)
        end
      end

      def lock_available?(path)
        return true unless path.exist?

        File.open(path, File::RDWR) do |file|
          locked = file.flock(File::LOCK_EX | File::LOCK_NB)
          file.flock(File::LOCK_UN) if locked
          locked
        end
      rescue Errno::ENOENT
        true
      end

      def validate_archive_entries!(entries)
        raise UnsafeRestore, "Backup is empty" if entries.empty?

        entries.each do |entry|
          clean = Pathname.new(entry).cleanpath
          top = clean.each_filename.first
          if clean.absolute? || clean.to_s == ".." || clean.to_s.start_with?("../") || !DURABLE_ENTRIES.include?(top)
            raise UnsafeRestore, "Backup contains an unsafe entry"
          end
        end
        missing = %w[instance.yml secret_key_base].reject { |required| entries.include?(required) }
        raise UnsafeRestore, "Backup is missing #{missing.join(', ')}" if missing.any?
      end
  end
end
