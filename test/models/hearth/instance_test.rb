require "test_helper"
require "digest"
require "open3"
require "tmpdir"
require "rubygems/package"
require "stringio"
require "zlib"

class Hearth::InstanceTest < ActiveSupport::TestCase
  test "initializes one secure directory scoped instance and resolves four roles" do
    Dir.mktmpdir("hearth-instance") do |root|
      instance = Hearth::Instance.new(root).initialize!

      assert_predicate instance, :ready?
      assert_equal 0o700, File.stat(instance.hearth_root).mode & 0o777
      [ instance.marker_path, instance.secret_path, instance.log_path.join("production.log") ].each do |path|
        assert_equal 0o600, File.stat(path).mode & 0o777
      end
      assert_equal 4, instance.database_paths.values.uniq.length
      assert_equal instance.uploads_path.to_s, instance.environment.fetch("HEARTH_STORAGE_ROOT")
      assert_equal instance.tmp_path.to_s, instance.environment(runtime: true).fetch("HEARTH_TMP")
      refute_includes instance.environment(runtime: true), "RAILS_TMP"
      refute_includes instance.environment(runtime: true), "RAILS_LOG_TO_STDOUT"
      assert_raises(Hearth::Instance::AlreadyInitialized) { instance.initialize! }
      assert_predicate instance, :ready?
      assert_predicate instance.secret_path, :file?
    end
  end

  test "uninitialized checks are read only" do
    Dir.mktmpdir("hearth-uninitialized") do |root|
      instance = Hearth::Instance.new(root)

      assert_raises(Hearth::Instance::Uninitialized) { instance.require_initialized! }
      assert_empty Dir.children(root)
    end
  end

  test "backup and restore preserve durable state and exclude logs and tmp" do
    Dir.mktmpdir("hearth-backup") do |workspace|
      source_root = File.join(workspace, "source")
      restore_root = File.join(workspace, "restore")
      FileUtils.mkdir_p([ source_root, restore_root ])
      source = Hearth::Instance.new(source_root).initialize!
      source.database_paths.each_value { |path| File.write(path, "role:#{path.basename}") }
      File.write(source.uploads_path.join("cover.bin"), "upload-bytes")
      File.write(source.log_path.join("private.log"), "excluded-log")
      File.write(source.tmp_path.join("stale.pid"), "123")
      secret_digest = Digest::SHA256.file(source.secret_path).hexdigest
      archive = File.join(workspace, "hearth.tgz")

      source.backup!(archive)
      restored = Hearth::Instance.new(restore_root).restore!(archive)

      assert_equal secret_digest, Digest::SHA256.file(restored.secret_path).hexdigest
      assert_equal "upload-bytes", restored.uploads_path.join("cover.bin").read
      source.database_paths.keys.each do |role|
        assert_equal source.database_paths.fetch(role).read, restored.database_paths.fetch(role).read
      end
      refute restored.log_path.exist?
      refute restored.tmp_path.exist?
      assert_equal 0o600, File.stat(archive).mode & 0o777
      assert_equal 0o700, File.stat(restored.hearth_root).mode & 0o777
    end
  end

  test "version is source controlled and does not boot Rails or require git" do
    Dir.mktmpdir("hearth-version") do |root|
      stdout, stderr, status = Open3.capture3(
        RbConfig.ruby, Rails.root.join("bin/hearth").to_s, "version", chdir: root
      )

      assert_predicate status, :success?, stderr
      assert_equal "0.1.0\n", stdout
      refute File.exist?(File.join(root, ".git"))
      refute File.exist?(File.join(root, ".hearth"))
    end
  end

  test "source checkout ignores instance secrets and databases" do
    ignore = Rails.root.join(".gitignore").read
    nested_secret = Rails.root.join("hearth-home/.hearth/secret_key_base")
    _output, _error, status = Open3.capture3("git", "check-ignore", "-q", "--", nested_secret.to_s,
      chdir: Rails.root)

    assert_includes ignore.lines.map(&:strip), ".hearth/"
    assert_predicate status, :success?, "nested instance secrets must be ignored"
  end

  test "backup rejects symlinks and restore rejects traversal entries" do
    Dir.mktmpdir("hearth-archive-safety") do |workspace|
      source_root = File.join(workspace, "source")
      restore_root = File.join(workspace, "restore")
      FileUtils.mkdir_p([ source_root, restore_root ])
      source = Hearth::Instance.new(source_root).initialize!
      File.symlink(source.secret_path, source.storage_path.join("linked-secret"))
      assert_raises(Hearth::Instance::Error) { source.backup!(File.join(workspace, "linked.tgz")) }

      archive = File.join(workspace, "unsafe.tgz")
      tar_buffer = StringIO.new(String.new)
      Gem::Package::TarWriter.new(tar_buffer) do |tar|
        tar.add_file("../escape", 0o600) { |file| file.write("unsafe") }
      end
      Zlib::GzipWriter.open(archive) do |gzip|
        gzip.write(tar_buffer.string)
      end
      restored = Hearth::Instance.new(restore_root)
      assert_raises(Hearth::Instance::UnsafeRestore) { restored.restore!(archive) }
      assert_empty Dir.children(restore_root)
      refute File.exist?(File.join(workspace, "escape"))
    end
  end

  test "restore into a nonempty root preserves the existing instance" do
    Dir.mktmpdir("hearth-restore-existing") do |workspace|
      source_root = File.join(workspace, "source")
      existing_root = File.join(workspace, "existing")
      FileUtils.mkdir_p([ source_root, existing_root ])
      source = Hearth::Instance.new(source_root).initialize!
      archive = source.backup!(File.join(workspace, "hearth.tgz"))
      existing = Hearth::Instance.new(existing_root).initialize!
      secret_digest = Digest::SHA256.file(existing.secret_path).hexdigest

      assert_raises(Hearth::Instance::UnsafeRestore) { existing.restore!(archive) }

      assert_predicate existing, :ready?
      assert_equal secret_digest, Digest::SHA256.file(existing.secret_path).hexdigest
    end
  end
end
