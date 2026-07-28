# Hearth — agent orientation

Self-hosted **holistic household health** app (Rails + Hotwire). One install, your data. Not multi-tenant SaaS.

## What Hearth is

Hearth is the system of record for a small household’s **daily health operations**: what you eat, how you train, how you sleep, habits, and an optional AI coach that plans and adjusts from that data.

**Content** (recipes, workout templates, protocol notes) may start life as markdown (e.g. a separate catalog repo). **Runtime data** lives in the app database.

## What Hearth will do

### Core (near-term)

| Area | Behavior |
|------|----------|
| **Meals** | Recipe catalog, logging what was eaten, meal plans, shopping-oriented views |
| **Training** | Workout templates, session logs, weekly dose targets |
| **Habits / recovery** | Sauna, lights-out, water, post-meal movement, etc. |
| **Household** | Multiple people (e.g. partners) on one instance; shared + per-person views |
| **Coach (optional)** | LLM tools over *this* DB + catalog: propose weeks, adapt from feedback |
| **Self-host** | Docker/Kamal-friendly; owner keeps data |

### Health integrations (planned)

| Area | Behavior |
|------|----------|
| **HealthKit (iOS companion)** | Thin native app reads Apple Health; posts samples/summaries into Hearth |
| **Manual + device logs** | Capture when no phone API |

### Sleep (planned — holistic loop)

| Area | Behavior |
|------|----------|
| **Ingest raw sleep-related signals** | e.g. HR, HRV, motion, stages/samples from HealthKit or other sources |
| **Derive sleep states / quality** | Process raw series into usable states (asleep/awake, stages if available, scores, trends) |
| **Surface sleep in the product** | Night timeline, readiness, correlation with training/meals/habits |
| **Actuation (later)** | Drive environment from sleep state — e.g. **change thermostat / room temperature** (and similar actuators) based on detected sleep phase or schedule |

Sleep is not a bolt-on tracker only: it is part of the same household health graph as food and training, and eventually **closes the loop into the environment**.

### Out of scope (for Botster / platform)

- Hearth is **not** a Botster plugin runtime requirement.
- Botster should **not** own HealthKit entitlements; health device access stays in a dedicated client or Hearth’s iOS companion.

## Data model intent

| Kind | Storage |
|------|---------|
| Recipes, workout templates, protocol packs | **DB** (imported/seeded from markdown or admin UI) |
| Meal logs, workout logs, habit check-ins | **DB** |
| Sleep raw samples + derived states | **DB** |
| Device/actuator config & history | **DB** |
| Source markdown catalogs | Optional external vault/repo; not the live store |

Markdown is for **authoring and versioning content**. Postgres/SQLite is for **queryable product state**.

## Stack (current scaffold)

- Rails 8.1, Propshaft, importmap, Turbo, Stimulus, Tailwind
- SQLite default; Solid Queue / Cache / Cable
- Kamal + Docker for deploy
- License: O'Saasy (self-host OK; no competing hosted SaaS of the product)

## Agent working rules

1. Prefer **Hotwire HTML-first** UI (server-rendered, Turbo Streams, Stimulus via data attributes). No SPA framework unless explicitly requested.
2. Prefer **importmap + no Node JS build** for app JS.
3. Keep features **self-host and multi-person household** friendly.
4. Do not put secrets or PII in the repo.
5. Medical disclaimer: tracking and automation tools — not medical advice or FDA-style device software unless explicitly redesigned as such.
6. When importing catalog content (e.g. Blueprint-inspired meals), keep attribution/status fields (`verified` / `adapted` / `observed`) and do not claim clinical endorsement.

## Suggested build order (guidance)

1. Household + people + auth  
2. Recipes + meal logs  
3. Workouts + session logs  
4. Habits / recovery check-ins  
5. Week views + plans  
6. Coach tools over DB  
7. HealthKit companion → sample ingest  
8. Sleep derivation pipeline  
9. Environment actuators (temperature, etc.) gated by user config and safety limits  

## Related local content (optional)

A separate **Meals** markdown catalog may exist for protocol/recipe research. Hearth should **import** that into the database rather than parse the vault at runtime for every request.
