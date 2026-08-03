require "test_helper"
require "net/http"
require "open3"
require "rbconfig"
require "socket"
require "tmpdir"

class HearthLauncherTest < ActiveSupport::TestCase
  BIN = Rails.root.join("bin/hearth").to_s

  test "source launcher initializes serves restarts and cleans both child groups" do
    Dir.mktmpdir("hearth-launcher") do |root|
      stdout, stderr, status = Open3.capture3(RbConfig.ruby, BIN, "init", "--root", root)
      assert_predicate status, :success?, "#{stdout}\n#{stderr}"
      instance = Hearth::Instance.new(root)
      assert instance.database_paths.values.all?(&:file?)
      assert_equal 4, instance.database_paths.values.uniq.length
      doctor, doctor_error, doctor_status = Open3.capture3(RbConfig.ruby, BIN, "doctor", "--root", root)
      assert_predicate doctor_status, :success?, doctor_error
      assert_includes doctor, "database_roles_distinct: true"
      assert_includes doctor, "storage_instance_scoped: true"
      assert_includes doctor, "storage_root: #{instance.uploads_path}"
      assert_includes doctor, "tmp_instance_scoped: true"
      assert_includes doctor, "tmp_root: #{instance.tmp_path}"
      stdout, stderr, household_status = Open3.capture3(instance.environment, "bin/rails", "runner",
        'Household.create!(name: "Launcher household", installation_key: 1)', chdir: Rails.root.to_s)
      assert_predicate household_status, :success?, "#{stdout}\n#{stderr}"

      2.times do |iteration|
        port = available_port
        launcher = Process.spawn(
          RbConfig.ruby, BIN, "serve", "--root", root, "--port", port.to_s,
          pgroup: true, out: File::NULL, err: File::NULL
        )
        wait_for_http(port)
        acp_pid = wait_for_pid(instance.acp_pid_path)
        pids = [ launcher, wait_for_pid(instance.launcher_path.join("puma.pid")), acp_pid ].uniq
        response = Net::HTTP.get_response(URI("http://127.0.0.1:#{port}/up"))
        assert_equal "200", response.code
        if iteration.zero?
          wait_for_runtime_state(instance, "online")
          Process.kill("TERM", -acp_pid)
          wait_for_runtime_state(instance, "starting")
          replacement_pid = wait_for_pid_change(instance.acp_pid_path, acp_pid)
          wait_for_runtime_state(instance, "online")
          assert_process_gone(acp_pid)
          pids << replacement_pid
          assert_equal "200", Net::HTTP.get_response(URI("http://127.0.0.1:#{port}/up")).code
        end
        Process.kill("TERM", -launcher)
        _, status = Process.wait2(launcher)
        assert_predicate status, :success?
        pids.each { |pid| assert_process_gone(pid) }
        refute instance.launcher_pid_path.exist?
        refute instance.acp_pid_path.exist?
      ensure
        stop_process_group(launcher)
      end
    end
  end

  test "source launcher exhausts bounded ACP restart attempts and cleans web" do
    Dir.mktmpdir("hearth-launcher-exhaustion") do |root|
      instance = Hearth::Instance.new(root).initialize!
      stdout, stderr, prepared = Open3.capture3(instance.environment, "bin/rails", "db:prepare", chdir: Rails.root.to_s)
      assert_predicate prepared, :success?, "#{stdout}\n#{stderr}"
      port = available_port
      launcher = Process.spawn(
        RbConfig.ruby, BIN, "serve", "--root", root, "--port", port.to_s,
        pgroup: true, out: File::NULL, err: File::NULL
      )
      wait_for_http(port)
      web_pid = wait_for_pid(instance.launcher_path.join("puma.pid"))
      acp_pids = []

      4.times do
        acp_pid = wait_for_pid(instance.acp_pid_path)
        acp_pids << acp_pid
        Process.kill("TERM", -acp_pid)
        wait_for_pid_change(instance.acp_pid_path, acp_pid) if acp_pids.length < 4
      end

      _, status = wait_for_exit(launcher, timeout: 15)
      refute_predicate status, :success?
      ([ launcher, web_pid ] + acp_pids).each { |pid| assert_process_gone(pid) }
      refute instance.launcher_pid_path.exist?
      refute instance.acp_pid_path.exist?
    ensure
      stop_process_group(launcher)
    end
  end

  test "uninitialized instance commands write nothing" do
    Dir.mktmpdir("hearth-launcher-uninitialized") do |root|
      _stdout, stderr, status = Open3.capture3(RbConfig.ruby, BIN, "doctor", "--root", root)

      refute_predicate status, :success?
      assert_match(/not initialized/, stderr)
      assert_empty Dir.children(root)
    end
  end

  test "launcher accepts a numeric string port and rejects an out of range port" do
    Dir.mktmpdir("hearth-launcher-port") do |root|
      instance = Hearth::Instance.new(root).initialize!

      assert_equal 3000, Hearth::Launcher.new(instance: instance, port: "3000").port
      assert_raises(ArgumentError) { Hearth::Launcher.new(instance: instance, port: "0") }
    end
  end

  test "a stable ACP run resets the bounded restart budget" do
    Dir.mktmpdir("hearth-launcher-stable") do |root|
      instance = Hearth::Instance.new(root).initialize!
      delays = []
      launcher = Hearth::Launcher.new(instance: instance,
        sleeper: ->(delay) { delays << delay }, monotonic_clock: -> { 11.0 })
      launcher.instance_variable_set(:@acp_restart_attempt, Hearth::Launcher::ACP_RESTART_BACKOFFS.length)
      launcher.instance_variable_get(:@child_specs)[:acp] = [ {}, [ RbConfig.ruby, "-e", "sleep 60" ] ]

      assert launcher.send(:restart_acp, started_at: 0.0)
      assert_equal [ Hearth::Launcher::ACP_RESTART_BACKOFFS.first ], delays
      assert_equal 1, launcher.children.length
    ensure
      launcher&.send(:stop_children)
    end
  end

  private
    def available_port
      server = TCPServer.new("127.0.0.1", 0)
      server.addr[1]
    ensure
      server&.close
    end

    def wait_for_http(port, timeout: 20)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
      loop do
        response = Net::HTTP.get_response(URI("http://127.0.0.1:#{port}/up"))
        return if response.is_a?(Net::HTTPSuccess)
      rescue Errno::ECONNREFUSED, Errno::ECONNRESET, EOFError
        raise "Hearth did not become ready" if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
        sleep 0.1
      end
    end

    def wait_for_pid(path, timeout: 20)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
      loop do
        pid = path.read.to_i
        return pid if pid.positive?

        raise "Hearth did not write #{path}" if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
        sleep 0.1
      rescue Errno::ENOENT
        raise "Hearth did not write #{path}" if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
        sleep 0.1
      end
    end

    def wait_for_pid_change(path, previous_pid, timeout: 20)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
      loop do
        pid = path.read.to_i
        return pid if pid.positive? && pid != previous_pid

        raise "Hearth did not replace #{previous_pid}" if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
        sleep 0.1
      rescue Errno::ENOENT
        raise "Hearth did not replace #{previous_pid}" if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
        sleep 0.1
      end
    end

    def wait_for_runtime_state(instance, expected, timeout: 20)
      database = SQLite3::Database.new(instance.database_paths.fetch("DATABASE_URL").to_s)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
      loop do
        state = database.get_first_value("SELECT status FROM agent_runtime_statuses ORDER BY id LIMIT 1")
        return if state == expected

        raise "Hearth ACP runtime did not become #{expected.inspect}; observed #{state.inspect}" if
          Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
        sleep 0.01
      rescue SQLite3::BusyException
        retry
      end
    ensure
      database&.close
    end

    def wait_for_exit(pid, timeout: 10)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
      loop do
        result = Process.wait2(pid, Process::WNOHANG)
        return result if result

        raise "Hearth launcher did not exit" if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
        sleep 0.1
      end
    end

    def assert_process_gone(pid, timeout: 5)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
      loop do
        Process.kill(0, pid)
        raise "process #{pid} was not reaped" if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
        sleep 0.05
      rescue Errno::ESRCH
        return
      end
    end

    def stop_process_group(pid)
      return unless pid
      Process.kill("TERM", -pid)
      Process.wait(pid)
    rescue Errno::ESRCH, Errno::ECHILD
      nil
    end
end
