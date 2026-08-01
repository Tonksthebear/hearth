class StabilizeAgentInstallationIdentity < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL.squish
      UPDATE agent_installations
      SET external_id = 'profile-' || profile_id
    SQL
  end

  def down
    # Provider-reported names were not stable identity and cannot be reconstructed.
  end
end
