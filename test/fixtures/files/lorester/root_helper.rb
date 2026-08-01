#!/usr/bin/env ruby

require "json"

vault = ARGV.fetch(ARGV.index("--vault") + 1)
sleep 60 if vault == "hang"
puts JSON.generate(
  ok: true,
  result: {
    vault_id: "vault-#{vault}",
    endpoint: ENV.fetch("LORESTER_DATA_DIR", "/missing-data-dir")
  }
)
