require "json"
require "rbconfig"

module Hearth
  class Launcher
    class Error < StandardError; end
    class AlreadyRunning < Error; end

    attr_reader :instance, :port, :children

    def initialize(instance:, port: 3000)
      @instance = instance.require_initialized!
      @port = Integer(port)
      raise ArgumentError, "Port must be between 1 and 65535" unless @port.between?(1, 65_535)

      @children = {}
      @stop_requested = false
    end

    def serve!
      instance.prepare_runtime!
      acquire!
      install_signal_handlers
      environment = instance.environment(port: port, runtime: true)
      spawn_child(:web, environment, RbConfig.ruby, Rails.root.join("bin/rails").to_s,
        "server", "--binding", "127.0.0.1", "--port", port.to_s)
      spawn_child(:acp, environment, RbConfig.ruby, Rails.root.join("bin/hearth-acp-runtime").to_s,
        "--root", instance.root.to_s)
      monitor!
    ensure
      stop_children
      release!
    end

    private
      def acquire!
        FileUtils.mkdir_p(instance.launcher_path, mode: Hearth::Instance::DIRECTORY_MODE)
        @lock = File.open(instance.launcher_lock_path, File::RDWR | File::CREAT, Hearth::Instance::FILE_MODE)
        File.chmod(Hearth::Instance::FILE_MODE, @lock.path)
        raise AlreadyRunning, "Hearth is already serving this instance" unless @lock.flock(File::LOCK_EX | File::LOCK_NB)

        File.write(instance.launcher_pid_path, "#{Process.pid}\n", mode: "w", perm: Hearth::Instance::FILE_MODE)
        File.chmod(Hearth::Instance::FILE_MODE, instance.launcher_pid_path)
      end

      def release!
        File.unlink(instance.launcher_pid_path) if instance.launcher_pid_path.file?
        @lock&.flock(File::LOCK_UN)
        @lock&.close unless @lock&.closed?
      rescue Errno::ENOENT
        nil
      end

      def install_signal_handlers
        %w[INT TERM].each { |signal| Signal.trap(signal) { @stop_requested = true } }
      end

      def spawn_child(component, environment, *command)
        pid = Process.spawn(environment, *command, pgroup: true, out: File::NULL, err: File::NULL)
        children[pid] = component
        record(component: component, category: "started")
      rescue SystemCallError => error
        record(component: component, category: "spawn_failed", error: error.class.name)
        raise Error, "Could not start #{component} (#{error.class.name})"
      end

      def monitor!
        until @stop_requested
          pid, status = Process.wait2(-1, Process::WNOHANG)
          unless pid
            sleep 0.1
            next
          end

          component = children.delete(pid)
          record(component: component, category: "exited", exit_code: status.exitstatus, signal: status.termsig)
          raise Error, "#{component} exited unexpectedly (#{status.exitstatus || "signal #{status.termsig}"})"
        end
      rescue Errno::ECHILD
        raise Error, "Hearth child processes exited"
      end

      def stop_children
        children.each_key do |pid|
          Process.kill("TERM", -pid)
        rescue Errno::ESRCH
          nil
        end
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 3
        until children.empty? || Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
          reap_one
          sleep 0.05 if children.any?
        end
        children.each_key do |pid|
          Process.kill("KILL", -pid)
        rescue Errno::ESRCH
          nil
        end
        reap_one until children.empty?
      end

      def reap_one
        pid, status = Process.wait2(-1, Process::WNOHANG)
        return unless pid

        component = children.delete(pid)
        record(component: component, category: "stopped", exit_code: status.exitstatus, signal: status.termsig)
      rescue Errno::ECHILD
        children.clear
      end

      def record(component:, category:, **metadata)
        path = instance.log_path.join("launcher.jsonl")
        File.open(path, "a", Hearth::Instance::FILE_MODE) do |file|
          file.puts(JSON.generate({ at: Time.now.utc.iso8601, component: component, category: category }.merge(metadata)))
        end
        File.chmod(Hearth::Instance::FILE_MODE, path)
      end
  end
end
