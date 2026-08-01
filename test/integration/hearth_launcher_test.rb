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

      2.times do
        port = available_port
        launcher = Process.spawn(
          RbConfig.ruby, BIN, "serve", "--root", root, "--port", port.to_s,
          pgroup: true, out: File::NULL, err: File::NULL
        )
        wait_for_http(port)
        pids = [ launcher, wait_for_pid(instance.launcher_path.join("puma.pid")),
          wait_for_pid(instance.acp_pid_path) ].uniq
        response = Net::HTTP.get_response(URI("http://127.0.0.1:#{port}/up"))
        assert_equal "200", response.code
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
