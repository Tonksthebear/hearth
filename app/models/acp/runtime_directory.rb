require "fileutils"
require "pathname"

module Acp
  class RuntimeDirectory
    class Error < StandardError; end
    class UninitializedInstance < Error; end
    class AlreadyRunning < Error; end

    attr_reader :instance, :instance_root, :path

    def initialize(instance_root:)
      @instance = Hearth::Instance.new(instance_root)
      @instance_root = instance.root
      @path = instance.acp_path
    end

    def acquire!
      instance.require_initialized!

      FileUtils.mkdir_p(path, mode: Hearth::Instance::DIRECTORY_MODE)
      File.chmod(Hearth::Instance::DIRECTORY_MODE, path)
      @lock = File.open(instance.acp_lock_path, File::RDWR | File::CREAT, Hearth::Instance::FILE_MODE)
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
      File.unlink(instance.acp_pid_path) if @owns_lock && instance.acp_pid_path.file?
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
        File.open(instance.acp_pid_path, File::WRONLY | File::CREAT | File::TRUNC, Hearth::Instance::FILE_MODE) do |file|
          file.write("#{Process.pid}\n")
          file.flush
          file.fsync
        end
        File.chmod(Hearth::Instance::FILE_MODE, instance.acp_pid_path)
      end
  end
end
