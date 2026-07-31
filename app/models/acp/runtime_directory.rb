require "fileutils"
require "pathname"

module Acp
  class RuntimeDirectory
    class Error < StandardError; end
    class UninitializedInstance < Error; end
    class AlreadyRunning < Error; end

    DIRECTORY_MODE = 0o700
    FILE_MODE = 0o600

    attr_reader :instance_root, :path

    def self.initialized_instance?(root)
      Pathname.new(root).expand_path.join(".hearth/instance.yml").file?
    end

    def initialize(instance_root:)
      @instance_root = Pathname.new(instance_root).expand_path
      @path = @instance_root.join(".hearth/tmp/acp")
    end

    def acquire!
      raise UninitializedInstance, "Hearth instance is not initialized at #{instance_root}" unless
        self.class.initialized_instance?(instance_root)

      FileUtils.mkdir_p(path, mode: DIRECTORY_MODE)
      File.chmod(DIRECTORY_MODE, path)
      @lock = File.open(path.join("supervisor.lock"), File::RDWR | File::CREAT, FILE_MODE)
      File.chmod(FILE_MODE, @lock.path)
      unless @lock.flock(File::LOCK_EX | File::LOCK_NB)
        raise AlreadyRunning, "An ACP runtime already owns #{instance_root}"
      end

      @owns_lock = true
      write_pid
      self
    rescue
      release!
      raise
    end

    def release!
      File.unlink(pid_path) if @owns_lock && pid_path&.file?
      @lock&.flock(File::LOCK_UN)
      @lock&.close unless @lock&.closed?
      @lock = nil
      @owns_lock = false
      nil
    rescue Errno::ENOENT
      nil
    end

    def acquired?
      @lock && !@lock.closed?
    end

    private
      def pid_path
        path.join("supervisor.pid")
      end

      def write_pid
        File.open(pid_path, File::WRONLY | File::CREAT | File::TRUNC, FILE_MODE) do |file|
          file.write("#{Process.pid}\n")
          file.flush
          file.fsync
        end
        File.chmod(FILE_MODE, pid_path)
      end
  end
end
