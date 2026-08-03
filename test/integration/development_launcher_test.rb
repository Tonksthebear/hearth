require "test_helper"
require "net/http"
require "open3"
require "socket"
require "tmpdir"

class DevelopmentLauncherTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  BIN = Rails.root.join("bin/dev").to_s
  RUNTIME_PID = Rails.root.join("tmp/acp/supervisor.pid")

  test "bin dev owns web css and ACP against isolated development databases" do
    unless foreman_available?
      flunk "Foreman is required after bin/setup" if ENV["HEARTH_REQUIRE_FOREMAN"] == "1"
      skip "Foreman is unavailable; run bin/setup before this focused launcher test"
    end

    Dir.mktmpdir("hearth-development-launcher") do |root|
      environment = development_environment(root, available_port)
      prepare_databases(environment)
      resolved = resolved_databases(environment)
      expected = %w[ primary cache queue cable ].to_h do |role|
        [ role, File.join(root, "#{role}.sqlite3") ]
      end
      assert_equal expected, resolved
      assert_equal 4, resolved.values.uniq.length
      original_storage = development_storage_snapshot
      output_path = File.join(root, "formation.log")

      formation = spawn_formation(environment, output_path)
      wait_for_http(environment.fetch("PORT").to_i)
      runtime_pid = wait_for_pid(RUNTIME_PID, output_path: output_path)
      wait_for_output(output_path, /waiting for database migrations and household setup/)
      assert_empty runtime_status_rows(environment)
      components = formation_components(formation)
      assert_equal 3, components.length, components.inspect
      assert_equal 1, components.count { |command| command.match?(/puma|rails server/) }, components.inspect
      assert_match(/css\.1\s+\| started with pid/, File.read(output_path))
      assert_equal 1, components.count { |command| command.include?("hearth-acp-runtime") }, components.inspect
      refute Rails.root.join(".hearth").exist?

      create_household(environment)
      wait_for_runtime_online(environment, output_path: output_path)
      assert_equal runtime_pid, wait_for_pid(RUNTIME_PID)
      assert_equal original_storage, development_storage_snapshot

      FileUtils.touch(Rails.root.join("tmp/restart.txt"))
      sleep 0.5
      assert_equal runtime_pid, wait_for_pid(RUNTIME_PID)

      Process.kill("TERM", runtime_pid)
      wait_for_exit(formation)
      wait_for_output(output_path, /system \| sending SIGTERM to all processes/)
      assert_process_gone(runtime_pid)
      refute RUNTIME_PID.exist?

      formation = spawn_formation(environment, output_path)
      wait_for_http(environment.fetch("PORT").to_i)
      replacement_pid = wait_for_pid(RUNTIME_PID, output_path: output_path)
      refute_equal runtime_pid, replacement_pid
      Process.kill("TERM", -formation)
      _, status = Process.wait2(formation)
      assert_predicate status, :success?
      assert_process_gone(replacement_pid)
      refute RUNTIME_PID.exist?
    ensure
      stop_process_group(formation)
    end
  end

  private
    def foreman_available?
      Bundler.with_unbundled_env do
        system("foreman", "--version", out: File::NULL, err: File::NULL)
      end
    end

    def development_environment(root, port)
      {
        "RAILS_ENV" => "development",
        "CI" => nil,
        "DATABASE_URL" => nil,
        "PORT" => port.to_s,
        "PRIMARY_DATABASE_URL" => "sqlite3:#{File.join(root, "primary.sqlite3")}",
        "CACHE_DATABASE_URL" => "sqlite3:#{File.join(root, "cache.sqlite3")}",
        "QUEUE_DATABASE_URL" => "sqlite3:#{File.join(root, "queue.sqlite3")}",
        "CABLE_DATABASE_URL" => "sqlite3:#{File.join(root, "cable.sqlite3")}",
        "HEARTH_MCP_URL" => "http://127.0.0.1:#{port}/mcp"
      }
    end

    def prepare_databases(environment)
      stdout, stderr, status = Open3.capture3(environment, "bin/rails", "db:prepare", chdir: Rails.root.to_s)
      assert_predicate status, :success?, "#{stdout}\n#{stderr}"
    end

    def create_household(environment)
      script = 'Household.create!(name: "Development launcher", installation_key: 1)'
      stdout, stderr, status = Open3.capture3(environment, "bin/rails", "runner", script, chdir: Rails.root.to_s)
      assert_predicate status, :success?, "#{stdout}\n#{stderr}"
    end

    def resolved_databases(environment)
      script = <<~'RUBY'
        configs = ActiveRecord::Base.configurations.configs_for(env_name: "development").index_by(&:name)
        puts configs.transform_values { |config| File.expand_path(config.database, Rails.root) }.to_json
      RUBY
      stdout, stderr, status = Open3.capture3(environment, "bin/rails", "runner", script, chdir: Rails.root.to_s)
      assert_predicate status, :success?, "#{stdout}\n#{stderr}"
      JSON.parse(stdout.lines.last)
    end

    def runtime_status_rows(environment)
      script = "puts Agent::RuntimeStatus.order(:id).pluck(:owner, :status).to_json"
      stdout, stderr, status = Open3.capture3(environment, "bin/rails", "runner", script, chdir: Rails.root.to_s)
      assert_predicate status, :success?, stderr
      JSON.parse(stdout.lines.last)
    end

    def wait_for_runtime_online(environment, timeout: 20, output_path: nil)
      deadline = monotonic_now + timeout
      loop do
        rows = runtime_status_rows(environment)
        return rows if rows.one? && rows.first.last == "online"
        if monotonic_now >= deadline
          details = output_path ? "\n#{File.read(output_path)}" : ""
          raise "Development ACP did not begin heartbeating: #{rows.inspect}#{details}"
        end
        sleep 0.2
      end
    end

    def spawn_formation(environment, output_path)
      output = File.open(output_path, "a")
      Bundler.with_unbundled_env do
        Process.spawn(environment, BIN, pgroup: true, out: output, err: output, chdir: Rails.root.to_s)
      end
    ensure
      output&.close
    end

    def formation_components(formation)
      rows = `ps -axo pid=,ppid=,command=`.lines.filter_map do |line|
        pid, ppid, command = line.strip.split(/\s+/, 3)
        [ pid.to_i, ppid.to_i, command.to_s ] if pid && ppid
      end
      descendants = rows.select { |_pid, ppid, _command| ppid == formation }
      descendants.map(&:last)
    end

    def development_storage_snapshot
      Rails.root.glob("storage/development*.sqlite3*").to_h do |path|
        [ path.to_s, [ path.size, path.mtime.to_f ] ]
      end
    end

    def available_port
      server = TCPServer.new("127.0.0.1", 0)
      server.addr[1]
    ensure
      server&.close
    end

    def wait_for_http(port, timeout: 20)
      deadline = monotonic_now + timeout
      loop do
        response = Net::HTTP.get_response(URI("http://127.0.0.1:#{port}/up"))
        return if response.is_a?(Net::HTTPSuccess)
      rescue Errno::ECONNREFUSED, Errno::ECONNRESET, EOFError
        raise "Development web process did not become ready" if monotonic_now >= deadline
        sleep 0.1
      end
    end

    def wait_for_pid(path, timeout: 20, output_path: nil)
      deadline = monotonic_now + timeout
      loop do
        pid = path.read.to_i
        return pid if pid.positive?
        raise "Development ACP did not write #{path}\n#{File.read(output_path)}" if monotonic_now >= deadline && output_path
        raise "Development ACP did not write #{path}" if monotonic_now >= deadline
        sleep 0.1
      rescue Errno::ENOENT
        raise "Development ACP did not write #{path}\n#{File.read(output_path)}" if monotonic_now >= deadline && output_path
        raise "Development ACP did not write #{path}" if monotonic_now >= deadline
        sleep 0.1
      end
    end

    def wait_for_output(path, pattern, timeout: 20)
      deadline = monotonic_now + timeout
      loop do
        return if File.read(path).match?(pattern)
        raise "Formation did not report #{pattern.inspect}" if monotonic_now >= deadline
        sleep 0.1
      end
    end

    def wait_for_exit(pid, timeout: 10)
      deadline = monotonic_now + timeout
      loop do
        result = Process.wait2(pid, Process::WNOHANG)
        return result if result
        raise "Formation #{pid} did not exit" if monotonic_now >= deadline
        sleep 0.1
      end
    end

    def assert_process_gone(pid, timeout: 5)
      deadline = monotonic_now + timeout
      loop do
        Process.kill(0, pid)
        raise "process #{pid} survived formation shutdown" if monotonic_now >= deadline
        sleep 0.05
      rescue Errno::ESRCH
        return
      end
    end

    def stop_process_group(pid)
      return unless pid
      Process.kill("TERM", -pid)
      Process.wait(pid)
    rescue Errno::ESRCH, Errno::ECHILD, Errno::EPERM
      nil
    end

    def monotonic_now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
end
