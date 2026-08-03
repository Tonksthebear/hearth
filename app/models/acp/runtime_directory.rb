require "fileutils"
require "pathname"

module Acp
  class RuntimeDirectory
    class Error < StandardError; end
    class UninitializedInstance < Error; end
    class AlreadyRunning < Error; end

    attr_reader :instance, :instance_root, :path

    def initialize(instance_root:, development: false)
      @instance = Hearth::Instance.new(instance_root)
      @instance_root = instance.root
      @development = development
      @path = development ? instance.root.join("tmp/acp") : instance.acp_path
    end

    def acquire!
      return self if acquired?

      instance.require_initialized! unless @development

      FileUtils.mkdir_p(path, mode: Hearth::Instance::DIRECTORY_MODE)
      File.chmod(Hearth::Instance::DIRECTORY_MODE, path)
      @lock = File.open(lock_path, File::RDWR | File::CREAT, Hearth::Instance::FILE_MODE)
      File.chmod(Hearth::Instance::FILE_MODE, @lock.path)
      unless @lock.flock(File::LOCK_EX | File::LOCK_NB)
        raise AlreadyRunning, "An ACP runtime already owns #{instance_root}"
      end

      @owns_lock = true
      write_pid
      self
    rescue Hearth::Instance::Uninitialized => error
      release!
      raise UninitializedInstance, error.message
    rescue
      release!
      raise
    end

    def release!
      File.unlink(pid_path) if @owns_lock && pid_path.file?
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
      def write_pid
        File.open(pid_path, File::WRONLY | File::CREAT | File::TRUNC, Hearth::Instance::FILE_MODE) do |file|
          file.write("#{Process.pid}\n")
          file.flush
          file.fsync
        end
        File.chmod(Hearth::Instance::FILE_MODE, pid_path)
      end

      def lock_path = path.join("supervisor.lock")
      def pid_path = path.join("supervisor.pid")
  end
end
