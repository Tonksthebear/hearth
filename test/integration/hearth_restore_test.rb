require "test_helper"
require "digest"
require "open3"
require "rbconfig"
require "tmpdir"

class HearthRestoreTest < ActiveSupport::TestCase
  BIN = Rails.root.join("bin/hearth").to_s

  test "backup restores secret four roles upload and a recoverable ACP session into an isolated root" do
    Dir.mktmpdir("hearth-restore-proof") do |workspace|
      source_root = File.join(workspace, "source")
      restored_root = File.join(workspace, "restored")
      archive = File.join(workspace, "hearth.tgz")
      FileUtils.mkdir_p([ source_root, restored_root ])
      run_hearth!("init", "--root", source_root)
      source = Hearth::Instance.new(source_root)
      secret_digest = Digest::SHA256.file(source.secret_path).hexdigest

      provision = <<~'RUBY'
        require "sqlite3"
        require "stringio"
        begin
        household = Household.create!(name: "Restore proof household", installation_key: 1)
        person = household.people.create!(name: "Restore proof person")
        profile = household.agent_profiles.create!(
          name: "Restore fake ACP", executable_path: RbConfig.ruby,
          arguments: [ Rails.root.join("test/fixtures/files/acp/fake_agent.rb").to_s ],
          environment_keys: %w[FAKE_ACP_MODE FAKE_SESSION_ID]
        )
        conversation = household.agent_conversations.create!(person: person, profile: profile, title: "Restore proof")
        supervisor = Acp::Supervisor.new(instance_root: ARGV.fetch(0)).start!
        session = supervisor.start_session(conversation: conversation)
        supervisor.shutdown!
        blob = ActiveStorage::Blob.create_and_upload!(
          io: StringIO.new("restore-upload-bytes"), filename: "restore.txt", content_type: "text/plain"
        )
        ActiveRecord::Base.configurations.configs_for(env_name: "production").each do |configuration|
          database = SQLite3::Database.new(configuration.database)
          database.execute("CREATE TABLE restore_proofs (value TEXT NOT NULL)")
          database.execute("INSERT INTO restore_proofs (value) VALUES (?)", [ configuration.name ])
          database.close
        end
        puts [ session.id, blob.id ].join(":")
        ensure
          supervisor&.shutdown!
        end
      RUBY
      proof = run_runner!(source, provision, source_root, "FAKE_ACP_MODE" => "normal", "FAKE_SESSION_ID" => "restore-session")
      session_id, blob_id = proof.lines.last.strip.split(":").map(&:to_i)

      run_hearth!("backup", archive, "--root", source_root)
      run_hearth!("restore", archive, "--root", restored_root)
      restored = Hearth::Instance.new(restored_root)

      assert_equal secret_digest, Digest::SHA256.file(restored.secret_path).hexdigest
      refute restored.log_path.exist?
      refute restored.tmp_path.exist?
      verify = <<~'RUBY'
        require "sqlite3"
        begin
        session = Agent::Session.find(Integer(ARGV.fetch(0)))
        blob = ActiveStorage::Blob.find(Integer(ARGV.fetch(1)))
        raise "upload changed" unless blob.download == "restore-upload-bytes"
        roles = ActiveRecord::Base.configurations.configs_for(env_name: "production").to_h do |configuration|
          database = SQLite3::Database.new(configuration.database)
          value = database.get_first_value("SELECT value FROM restore_proofs")
          database.close
          [ configuration.name, value ]
        end
        raise "role proof changed: #{roles.inspect}" unless roles == roles.keys.index_with(&:itself)
        supervisor = Acp::Supervisor.new(instance_root: ARGV.fetch(2)).start!
        recovered = supervisor.recover_session(session)
        raise recovered.recovery_error unless recovered.status == "connected"
        puts "restored=#{roles.keys.sort.join(',')};session=#{recovered.status};upload=ok"
        ensure
          supervisor&.shutdown!
        end
      RUBY
      output = run_runner!(
        restored, verify, session_id.to_s, blob_id.to_s, restored_root,
        "FAKE_ACP_MODE" => "normal", "FAKE_SESSION_ID" => "restore-session"
      )
      assert_includes output, "restored=cable,cache,primary,queue;session=connected;upload=ok"
      refute_equal source.root, restored.root
    end
  end

  private
    def run_hearth!(*arguments)
      stdout, stderr, status = Open3.capture3(RbConfig.ruby, BIN, *arguments)
      assert_predicate status, :success?, "#{stdout}\n#{stderr}"
      stdout
    end

    def run_runner!(instance, code, *arguments, **extra_environment)
      environment = instance.environment.merge(extra_environment)
      stdout, stderr, status = Open3.capture3(
        environment, RbConfig.ruby, Rails.root.join("bin/rails").to_s, "runner", code, *arguments
      )
      assert_predicate status, :success?, "#{stdout}\n#{stderr}"
      stdout
    end
end
