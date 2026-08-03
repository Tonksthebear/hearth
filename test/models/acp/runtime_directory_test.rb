require "test_helper"
require "tmpdir"

class Acp::RuntimeDirectoryTest < ActiveSupport::TestCase
  test "refuses an uninitialized root without writing anything" do
    Dir.mktmpdir("hearth-uninitialized") do |root|
      runtime_directory = Acp::RuntimeDirectory.new(instance_root: root)

      assert_raises(Acp::RuntimeDirectory::UninitializedInstance) { runtime_directory.acquire! }
      assert_empty Dir.children(root)
      refute File.exist?(File.join(root, ".hearth"))
    end
  end

  test "uses only dot hearth tmp acp with restrictive modes and rejects a second owner" do
    with_instance_root do |root|
      first = Acp::RuntimeDirectory.new(instance_root: root).acquire!
      second = Acp::RuntimeDirectory.new(instance_root: root)
      path = File.join(root, ".hearth/tmp/acp")

      assert_equal 0o700, File.stat(path).mode & 0o777
      assert_equal 0o600, File.stat(File.join(path, "supervisor.lock")).mode & 0o777
      assert_equal 0o600, File.stat(File.join(path, "supervisor.pid")).mode & 0o777
      assert_raises(Acp::RuntimeDirectory::AlreadyRunning) { second.acquire! }

      first.release!
      refute File.exist?(File.join(path, "supervisor.pid"))
      assert second.acquire!
      second.release!
    ensure
      first&.release!
      second&.release!
    end
  end

  test "development ownership uses checkout tmp without initializing an instance" do
    Dir.mktmpdir("hearth-development-runtime") do |root|
      runtime_directory = Acp::RuntimeDirectory.new(instance_root: root, development: true).acquire!

      assert_equal File.join(root, "tmp/acp"), runtime_directory.path.to_s
      assert File.exist?(File.join(root, "tmp/acp/supervisor.pid"))
      refute File.exist?(File.join(root, ".hearth"))

      runtime_directory.release!
      refute File.exist?(File.join(root, "tmp/acp/supervisor.pid"))
    ensure
      runtime_directory&.release!
    end
  end

  private
    def with_instance_root
      Dir.mktmpdir("hearth-instance") do |root|
        Hearth::Instance.new(root).initialize!
        yield root
      end
    end
end
