# Hearth

Hearth is a self-hosted household health app for meals, training, habits, and recovery. One installation serves one household; it is not a multi-tenant SaaS, and the operator keeps the data.

The current alpha includes household setup and sign-in, multiple people, recipes and meal planning/logging, shopping views, workout templates and session logs, habits/recovery check-ins, and weekly operating views.

## Nutrition tracking

Hearth starts with an extensible reference catalog for energy, protein, carbohydrates, fat, fiber, and sodium. Ingredient values are recorded per 100 grams from the Recipes area. Blank means unknown; an explicitly entered zero remains a known zero. Recipe estimates use only explicit ingredient gram weights and serving counts, and source-provided per-serving facts override estimates one nutrient at a time.

Meal nutrition is snapshotted when a meal item's source or portion is saved. Later recipe, ingredient, or catalog edits do not rewrite that history. Unsupported or missing portions remain visibly incomplete and are never treated as zero. These are household tracking tools, not medical advice.

USDA FoodData Central import is optional and operator-triggered; normal browser and MCP reads never contact it. Configure `FDC_API_KEY` outside the repository (or the `food_data_central.api_key` Rails credential), then import one known food ID into an existing ingredient:

```bash
FDC_API_KEY=... bin/rails "nutrition:import_fdc[INGREDIENT_ID,FDC_FOOD_ID]"
```

The importer records USDA attribution, accepts only recognized nutrient identifier/unit pairs, and never persists the API key.

## Before you run it

Choose one first-run path:

- **Setup-first (recommended):** start with an empty database, open Hearth, and create your household and first user.
- **Demo:** opt in with `HEARTH_DEMO_DATA=1` and `HEARTH_DEMO_PASSWORD`. This loads a generic, PII-free household and representative meal, training, and habit history.

Hearth permits exactly one household. Demo data therefore consumes the installation's only household slot and disables first-run setup. To return to setup-first, use a new empty database or Docker volume; do not run demo seeds against a real household. Re-running the demo seed is safe and updates the same recognized demo graph.

## Local development

Requirements are Ruby 3.4.2, SQLite, and the packages needed by the bundled gems. JavaScript uses importmap; there is no Node build.

The supervised ACP runtime and authenticated guarded MCP operations are documented in
[docs/acp-supported-agent-contract.md](docs/acp-supported-agent-contract.md).
`bin/hearth-acp-runtime` is the production-shaped, standalone ACP process host.
It requires an already initialized directory containing `.hearth/instance.yml`,
runs separately from Puma, and injects a short-lived server-issued `Agent::Grant`
into the first ACP session request and every recovery. Rails serves the canonical
stateless MCP endpoint at loopback-only `POST /mcp`; agents without ACP HTTP MCP
support receive the thin `bin/hearth-mcp-proxy` stdio relay instead.
Runtime grants expire after 15 minutes or 200 tool calls, with a 200,000-token
output budget. The first request after expiry or exhaustion marks the persisted
session as requiring MCP reauthorization; recovering or restarting it injects a fresh
credential because ACP MCP configuration is immutable after session selection.

Every ACP session starts with `health_read`, `knowledge_read`, and
`knowledge_submit`. Knowledge submission is proposal authority only: conversation
content remains in Hearth until a same-household user approves its durable permission
request, and Lorester alone materializes the approved capture. An authenticated household user can
enable short-lived operational access for the exact conversation, selected person, and
browser session. Recovery then injects a fresh digest-only `health_read` + `health_write`
grant alongside the knowledge groups. Consequential operations appear in Hearth for a one-time human decision before
execution; disabling access, changing person, signing out, disconnecting, or reaching
the earliest deadline fails pending changes closed.

To connect the local knowledge boundary, configure `LORESTER_VAULT` with the explicit
managed vault, optionally set `LORESTER_EXECUTABLE` (default: `lorester`), and set
`LORESTER_DATA_DIR` when the Lorester owner uses an external operational root. Hearth
runs `lorester --json root --vault VAULT` under the same effective user, performs the
required vault Hello on Lorester's resolved `0600` Unix socket, and then sends one
typed version-1 knowledge operation. Hearth never receives a generic filesystem,
Markdown, Git, shell, MOC, projection-database, or maintenance interface. Missing
configuration, stopped transport, unavailable projection, stale projection, and
incompatible contract remain distinct bounded results. Inbox status polling is limited
to once per second; normal Lorester reconciliation and processing may take longer.

The source checkout is not implicitly a Hearth instance, so `Procfile.dev` does
not start the ACP runtime. Development uses separate primary, cache, queue, and
cable SQLite files, and Solid Cable carries committed chat projections between
the web and runtime processes. Run the web process and durable turn consumer in
two terminals, using an explicit initialized instance root:

```bash
bin/dev
RAILS_ENV=development bin/hearth-acp-runtime --root /path/to/initialized/hearth-instance
```

The Coach form only commits a user message and pending `Agent::Turn`; it never
starts an ACP process in Puma. If a turn remains Pending, confirm the second
terminal is running, the selected profile is enabled, and the root contains
`.hearth/instance.yml`. Do not point multiple database roles at one shared URL.
The runtime polls the database as its authority, so a missed notification cannot
lose queued work.

Agent executable, argv, contained working directory, environment-name allowlist,
and manual update policy live on `Agent::Profile`. Session transport and recovery
truth live in the database; `.hearth/tmp/acp` contains only restrictive lock/PID
state. Ticket 09 will place this same executable beneath `hearth serve`.

## UI assets

Hearth’s browser UI uses locally synced Tailwind Plus Elements components,
the locally vendored `@tailwindplus/elements` importmap package, and a
generated warm-amber theme. Runtime use does not require the private source
component repository, a CDN, Node, or a JavaScript build.

The current component export came from the authorized
`tailwindplus_elements_components` source at commit
`4e5f273e1c9ed29d95de691988adeb9698e2852d`. Maintainers with access to that
licensed source can refresh the export with its `bin/sync export` command,
then regenerate
`app/assets/tailwind/tailwindplus_elements_components/theme.css` with:

```bash
bin/generate-theme --primary '#B45309' --secondary-offset 60 \
  --pull-strength 0.15 --push-strength 0.25 \
  -o /path/to/hearth/app/assets/tailwind/tailwindplus_elements_components/theme.css
```

Do not commit the source repository, its preview/reference tree, or an
absolute developer path. Heroicons and SlimSelect retain their upstream
license files alongside the vendored assets.

### Refreshing the Elements export

The component export is intentionally complete, including components Hearth
does not currently render, so a refresh remains a direct comparison with the
licensed source. Heroicons follow a different policy: they are not part of
`bin/sync export`, and only the icon names referenced by Hearth are retained
in the four shipped variants. When adding an icon, copy that name's `micro`,
`mini`, `solid`, and `outline` SVGs and keep
`app/assets/svg/icons/heroicons/LICENSE`.

A fresh export must be merged with these reviewed Hearth integration changes
before it is committed:

- `DropdownComponent`, `PopoverComponent`, and `SelectComponent` use
  `popover="auto"`; Select also wires its button to the options popover with
  native `command`/`commandfor` attributes.
- `vendor/javascript/tailwindplus_elements_components.js` waits for the
  required custom elements, marks `data-elements-ready`, resets readiness
  before Turbo visits, and destroys/reinitializes SlimSelect around Turbo
  caching, frames, and stream replacement. A per-`el-select`, bubbling event
  adapter synchronizes native option clicks; there is no document-global
  capture-phase click shim.
- The local form builder preserves boolean `false` values and renders the
  selected option text on the server; the tag helper resolves display text
  for `false` as well.

After a refresh, review those files rather than accepting the export
wholesale, regenerate the theme with the command above, run
`bin/rails tailwindcss:build`, and run `bin/ci`.

The production-shaped chat acceptance uses isolated temporary primary and cable
databases, real Chrome/Puma, Solid Cable, and a real sibling ACP runtime:

```bash
bin/agent-chat-acceptance
```

For setup-first, `bin/setup` prepares the database and starts `bin/dev`. Open [http://localhost:3000](http://localhost:3000) and complete household setup.

```bash
bin/setup
```

For the demo path, prepare without starting the server, then run the seed task explicitly. This works whether the development database is new or already prepared:

```bash
bin/setup --skip-server
read -s -p "Demo password: " HEARTH_DEMO_PASSWORD
printf "\n"
HEARTH_DEMO_DATA=1 HEARTH_DEMO_PASSWORD="$HEARTH_DEMO_PASSWORD" bin/rails db:seed
unset HEARTH_DEMO_PASSWORD
bin/dev
```

Sign in as `demo@hearth.local`.

## Run the production image with Docker

The verified alpha image path is Linux amd64. The host may use amd64 emulation, but native arm64 and other architectures have not been release-verified.

Generate the Rails signing secret once and keep it outside this repository. Reuse the same value for every restart, recreation, and upgrade; replacing it invalidates signed sessions and tokens.

```bash
mkdir -p "$HOME/.config/hearth"
chmod 700 "$HOME/.config/hearth"
umask 077
test -s "$HOME/.config/hearth/secret_key_base" ||
  openssl rand -hex 64 > "$HOME/.config/hearth/secret_key_base"
{
  printf "SECRET_KEY_BASE="
  cat "$HOME/.config/hearth/secret_key_base"
  printf "\nSOLID_QUEUE_IN_PUMA=true\n"
} > "$HOME/.config/hearth/docker.env"
```

`SECRET_KEY_BASE` is the only required runtime secret. Rails credentials or `FDC_API_KEY` are used only when the optional FoodData Central import is invoked.

Build and start:

```bash
docker buildx build --platform linux/amd64 --load -t hearth:alpha .
docker volume create hearth_storage
docker run -d \
  --name hearth \
  --platform linux/amd64 \
  --env-file "$HOME/.config/hearth/docker.env" \
  -p 3000:80 \
  -v hearth_storage:/rails/storage \
  hearth:alpha
curl --fail http://localhost:3000/up
```

Open [http://localhost:3000](http://localhost:3000) and complete setup. The container entrypoint prepares and migrates all four SQLite databases before the server starts, and `SOLID_QUEUE_IN_PUMA=true` runs the job supervisor in the single web container.

To choose demo data instead, add these two lines to the private env file before the first start. Prompt for the password so it does not enter shell history:

```bash
read -s -p "Demo password: " HEARTH_DEMO_PASSWORD
printf "\nHEARTH_DEMO_DATA=1\nHEARTH_DEMO_PASSWORD=%s\n" \
  "$HEARTH_DEMO_PASSWORD" >> "$HOME/.config/hearth/docker.env"
unset HEARTH_DEMO_PASSWORD
```

Restart and recreation retain data because the named volume is separate from the container:

```bash
docker restart hearth
curl --fail http://localhost:3000/up

docker stop hearth
docker rm hearth
docker run -d \
  --name hearth \
  --platform linux/amd64 \
  --env-file "$HOME/.config/hearth/docker.env" \
  -p 3000:80 \
  -v hearth_storage:/rails/storage \
  hearth:alpha
curl --fail http://localhost:3000/up
```

Removing a container does not remove the named volume. Removing `hearth_storage` does remove the household, logs, uploaded files, and all other application state.

## Storage and database overrides

The single `/rails/storage` mount contains:

- `production.sqlite3` — household and health-operation records
- `production_cache.sqlite3` — Solid Cache
- `production_queue.sqlite3` — Solid Queue
- `production_cable.sqlite3` — Solid Cable
- Active Storage originals and generated variants, including recipe cover images

Keep the whole directory together when backing up or restoring.

Abandoned recipe form uploads can leave unattached blobs. Periodically purge unattached blobs older than one day; the running Solid Queue supervisor removes their stored files asynchronously:

```bash
docker exec hearth bin/rails runner \
  'ActiveStorage::Blob.unattached.where(created_at: ..1.day.ago).find_each(&:purge_later)'
```

`DATABASE_URL` overrides the primary database. `CACHE_DATABASE_URL`, `QUEUE_DATABASE_URL`, and `CABLE_DATABASE_URL` independently override the three Solid databases while preserving their migration paths. If you relocate storage with URLs, set all four explicitly and keep them distinct. The supported alpha topology remains SQLite on one host with one web container and one shared storage mount.

## Backup and restore

Stop Hearth before copying SQLite so the web process and job supervisor cannot write during the backup:

```bash
mkdir -p "$HOME/.local/share/hearth/backups"
chmod 700 "$HOME/.local/share/hearth/backups"
docker stop hearth
docker run --rm \
  --user 0:0 \
  --entrypoint tar \
  -v hearth_storage:/rails/storage \
  -v "$HOME/.local/share/hearth/backups":/backup \
  hearth:alpha \
  -czf /backup/hearth-storage.tgz -C /rails/storage .
docker run --rm \
  --user 0:0 \
  --entrypoint chown \
  -v "$HOME/.local/share/hearth/backups":/backup \
  hearth:alpha \
  "$(id -u):$(id -g)" /backup/hearth-storage.tgz
chmod 600 "$HOME/.local/share/hearth/backups/hearth-storage.tgz"
docker start hearth
```

Store `$HOME/.local/share/hearth/backups/hearth-storage.tgz` somewhere protected and backed up. It contains private household health data and is intentionally outside the source checkout.

Test or perform a restore into a new volume without destroying the original:

```bash
docker volume create hearth_storage_restore
docker run --rm \
  --user 0:0 \
  --entrypoint tar \
  -v hearth_storage_restore:/rails/storage \
  -v "$HOME/.local/share/hearth/backups":/backup \
  hearth:alpha \
  -xzf /backup/hearth-storage.tgz -C /rails/storage
docker run -d \
  --name hearth-restore \
  --platform linux/amd64 \
  --env-file "$HOME/.config/hearth/docker.env" \
  -p 3001:80 \
  -v hearth_storage_restore:/rails/storage \
  hearth:alpha
curl --fail http://localhost:3001/up
```

Use the same `SECRET_KEY_BASE` when restoring. Confirm the recovered household and open a recipe with a cover image to verify both its database attachment and stored file before replacing the original volume.

## Upgrade and rollback

Before every upgrade:

1. Stop the current container.
2. Back up the entire storage volume.
3. Build or pull the new image.
4. Recreate the container with the same secret and volume.
5. Check `/up`, sign in, and inspect a representative meal, session, habit entry, and recipe cover image.

The entrypoint runs `db:prepare`, which applies forward migrations. A code rollback after a schema change may not be safe; restore the pre-upgrade whole-volume backup together with the prior image.

## Kamal single-host deployment

`config/deploy.yml` describes the same topology: one amd64 web host, `hearth_storage:/rails/storage`, `SOLID_QUEUE_IN_PUMA=true`, and the stable `SECRET_KEY_BASE`.

Create the secret file as shown above, set its path for Kamal's resolver, and confirm the configuration without recording the secret value:

```bash
export HEARTH_SECRET_KEY_BASE_FILE="$HOME/.config/hearth/secret_key_base"
bin/kamal secrets print | grep -Eq '^SECRET_KEY_BASE=.+'
bin/kamal config
bin/kamal setup
```

Before deployment, replace the example server and registry values in `config/deploy.yml`. A reachable remote Kamal deployment is not part of the local alpha verification.

The default configuration does not enable Kamal's TLS proxy. Use Hearth only on a trusted LAN or behind an operator-managed TLS-terminating reverse proxy configured with the correct host protections. Do not expose the default direct HTTP service to the public internet.

## Password recovery limitation

Password-reset email is not available out of the box: SMTP and the public mailer host are intentionally not configured in this alpha. Reset a password from an interactive Rails console:

```bash
docker exec -it hearth bin/rails console
```

Then enter:

```ruby
require "io/console"
user = User.find_by!(email_address: "you@example.com")
password = IO.console.getpass("New password: ")
user.update!(password: password, password_confirmation: password)
```

This keeps the new password out of shell history. Kamal operators can open the same console with `bin/kamal console`.

## Release checks

Run the complete release gate with:

```bash
bin/ci
```

It runs style and refreshed dependency/security scans, Rails and browser system tests, isolated demo-seed idempotency checks, four-database migration checks, production asset compilation, and production eager loading. Container persistence, backup/restore, and Solid Queue/Cache/Cable behavior are production-runtime checks performed against the built image.

## Alpha limitations and safety

- No AI coach or LLM planning tools.
- No HealthKit companion or sample ingestion.
- No sleep-state derivation, readiness scoring, or sleep timeline.
- No thermostat or other environment actuators.
- No built-in SMTP delivery, TLS termination, public-host hardening, or automated off-host backups.
- Verified image platform is Linux amd64; native arm64 and remote Kamal deployment remain unverified.
- Hearth is a tracking and automation tool, not medical advice, a diagnostic product, or regulated medical-device software.

## License

[O'Saasy License](LICENSE) — free to use and self-host; no competing hosted SaaS that resells the product's core functionality.
