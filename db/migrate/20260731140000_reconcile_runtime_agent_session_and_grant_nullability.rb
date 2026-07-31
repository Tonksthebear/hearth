class ReconcileRuntimeAgentSessionAndGrantNullability < ActiveRecord::Migration[8.1]
  COLUMNS = {
    agent_sessions: :external_session_id,
    agent_grants: :issued_by_id
  }.freeze

  def up
    columns = COLUMNS.to_h do |table, column|
      raise "Cannot reconcile runtime agent nullability: missing table #{table}" unless connection.table_exists?(table)

      definition = connection.columns(table).find { |candidate| candidate.name == column.to_s }
      raise "Cannot reconcile runtime agent nullability: missing column #{table}.#{column}" unless definition

      [ [ table, column ], definition ]
    end

    columns.each do |(table, column), definition|
      change_column_null table, column, true unless definition.null
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
      "Runtime agent rows may contain NULL session identifiers or grant issuers after reconciliation."
  end
end
