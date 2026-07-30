# Hearth

Hearth is a self-hosted household health app for meals, training, habits, and recovery. One installation serves one household; it is not a multi-tenant SaaS, and the operator keeps the data.

The current alpha includes household setup and sign-in, multiple people, recipes and meal planning/logging, shopping views, workout templates and session logs, habits/recovery check-ins, and weekly operating views.

## Before you run it

Choose one first-run path:

- **Setup-first (recommended):** start with an empty database, open Hearth, and create your household and first user.
- **Demo:** opt in with `HEARTH_DEMO_DATA=1` and `HEARTH_DEMO_PASSWORD`. This loads a generic, PII-free household and representative meal, training, and habit history.

Hearth permits exactly one household. Demo data therefore consumes the installation's only household slot and disables first-run setup. To return to setup-first, use a new empty database or Docker volume; do not run demo seeds against a real household. Re-running the demo seed is safe and updates the same recognized demo graph.

## Local development

Requirements are Ruby 3.4.2, SQLite, and the packages needed by the bundled gems. JavaScript uses importmap; there is no Node build.

```bash
bin/setup
```

`bin/setup` prepares the database and starts `bin/dev`. Open [http://localhost:3000](http://localhost:3000) and complete household setup.

For the demo path, capture a password without putting it in shell history:

```bash
read -s -p "Demo password: " HEARTH_DEMO_PASSWORD
printf "\n"
HEARTH_DEMO_DATA=1 HEARTH_DEMO_PASSWORD="$HEARTH_DEMO_PASSWORD" bin/setup
unset HEARTH_DEMO_PASSWORD
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

Rails credentials are not used by this alpha. `SECRET_KEY_BASE` is the only required runtime secret.

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
- Active Storage files

Keep the whole directory together when backing up or restoring.

`DATABASE_URL` overrides the primary database. `CACHE_DATABASE_URL`, `QUEUE_DATABASE_URL`, and `CABLE_DATABASE_URL` independently override the three Solid databases while preserving their migration paths. If you relocate storage with URLs, set all four explicitly and keep them distinct. The supported alpha topology remains SQLite on one host with one web container and one shared storage mount.

## Backup and restore

Stop Hearth before copying SQLite so the web process and job supervisor cannot write during the backup:

```bash
docker stop hearth
docker run --rm \
  --user 0:0 \
  --entrypoint tar \
  -v hearth_storage:/rails/storage \
  -v "$PWD":/backup \
  hearth:alpha \
  -czf /backup/hearth-storage.tgz -C /rails/storage .
docker start hearth
```

Store `hearth-storage.tgz` somewhere protected and backed up. It contains private household health data.

Test or perform a restore into a new volume without destroying the original:

```bash
docker volume create hearth_storage_restore
docker run --rm \
  --user 0:0 \
  --entrypoint tar \
  -v hearth_storage_restore:/rails/storage \
  -v "$PWD":/backup \
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

Use the same `SECRET_KEY_BASE` when restoring. Confirm the recovered household before replacing the original volume.

## Upgrade and rollback

Before every upgrade:

1. Stop the current container.
2. Back up the entire storage volume.
3. Build or pull the new image.
4. Recreate the container with the same secret and volume.
5. Check `/up`, sign in, and inspect a representative meal, session, and habit entry.

The entrypoint runs `db:prepare`, which applies forward migrations. A code rollback after a schema change may not be safe; restore the pre-upgrade whole-volume backup together with the prior image.

## Kamal single-host deployment

`config/deploy.yml` describes the same topology: one amd64 web host, `hearth_storage:/rails/storage`, `SOLID_QUEUE_IN_PUMA=true`, and the stable `SECRET_KEY_BASE`.

Create the secret file as shown above, set its path for Kamal's resolver, and confirm the configuration without recording the secret value:

```bash
export HEARTH_SECRET_KEY_BASE_FILE="$HOME/.config/hearth/secret_key_base"
bin/kamal secrets print | grep --quiet '^SECRET_KEY_BASE='
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
