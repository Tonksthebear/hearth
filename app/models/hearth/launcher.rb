require "json"
require "rbconfig"

module Hearth
  class Launcher
    class Error < StandardError; end
    class AlreadyRunning < Error; end

    ACP_RESTART_BACKOFFS = [ 0.25, 1, 4 ].freeze
    ACP_STABLE_AFTER = 10.seconds

    attr_reader :instance, :port, :children

    def initialize(instance:, port: 3000, sleeper: ->(duration) { sleep duration },
      monotonic_clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) })
      @instance = instance.require_initialized!
      @port = Integer(port)
      raise ArgumentError, "Port must be between 1 and 65535" unless @port.between?(1, 65_535)

      @children = {}
      @child_specs = {}
      @child_started_at = {}
      @sleeper = sleeper
      @monotonic_clock = monotonic_clock
      @acp_restart_attempt = 0
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
        @child_specs[component] = [ environment, command ]
        @child_started_at[pid] = monotonic_now
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
          started_at = @child_started_at.delete(pid)
          record(component: component, category: "exited", exit_code: status.exitstatus, signal: status.termsig)
          if component == :acp && restart_acp(started_at: started_at)
            next
          end
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
        @child_started_at.delete(pid)
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

      def restart_acp(started_at:)
        if started_at && monotonic_now - started_at >= ACP_STABLE_AFTER
          @acp_restart_attempt = 0
          record(component: :acp, category: "restart_budget_reset")
        end
        return false if @acp_restart_attempt >= ACP_RESTART_BACKOFFS.length

        delay = ACP_RESTART_BACKOFFS.fetch(@acp_restart_attempt)
        @acp_restart_attempt += 1
        restart_owner = "launcher-#{Process.pid}"
        Agent::RuntimeStatus.start_all!(owner: restart_owner)
        warn "Hearth ACP runtime exited; restarting in #{delay}s (attempt #{@acp_restart_attempt}/#{ACP_RESTART_BACKOFFS.length})"
        record(component: :acp, category: "restarting", delay: delay, attempt: @acp_restart_attempt)
        @sleeper.call(delay)
        if @stop_requested
          Agent::RuntimeStatus.stop_all!(owner: restart_owner)
          return true
        end

        environment, command = @child_specs.fetch(:acp)
        spawn_child(:acp, environment, *command)
        true
      rescue Error
        Agent::RuntimeStatus.stop_all!(owner: restart_owner, failed: true, failure_category: "runtime_error") if restart_owner
        raise
      end

      def monotonic_now = @monotonic_clock.call
  end
end
