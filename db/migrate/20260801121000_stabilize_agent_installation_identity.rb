class StabilizeAgentInstallationIdentity < ActiveRecord::Migration[8.1]
  def up
    duplicate_profile_installations.each do |household_id, profile_id|
      installations = select_all(<<~SQL.squish).to_a
        SELECT id, external_id
        FROM agent_installations
        WHERE household_id = #{quote(household_id)} AND profile_id = #{quote(profile_id)}
        ORDER BY CASE WHEN external_id = #{quote("profile-#{profile_id}")} THEN 0 ELSE 1 END,
          COALESCE(last_seen_at, updated_at, created_at) DESC,
          id DESC
      SQL
      canonical_id = installations.first.fetch("id")
      duplicate_ids = installations.drop(1).pluck("id")

      execute <<~SQL.squish
        UPDATE agent_sessions
        SET installation_id = #{quote(canonical_id)}
        WHERE installation_id IN (#{duplicate_ids.map { |id| quote(id) }.join(", ")})
      SQL
      execute <<~SQL.squish
        DELETE FROM agent_installations
        WHERE id IN (#{duplicate_ids.map { |id| quote(id) }.join(", ")})
      SQL
    end

    execute <<~SQL.squish
      UPDATE agent_installations
      SET external_id = 'profile-' || profile_id
    SQL
  end

  def down
    # Provider-reported names were not stable identity and cannot be reconstructed.
  end

  private
    def duplicate_profile_installations
      select_rows(<<~SQL.squish)
        SELECT household_id, profile_id
        FROM agent_installations
        GROUP BY household_id, profile_id
        HAVING COUNT(*) > 1
      SQL
    end

    def quote(value)
      connection.quote(value)
    end
end
