# Workout Guide catalog contract

Status: normative catalog and import-shape contract, version `workout_guide/v1`. Runtime import belongs to a later ticket. This document defines the pinned vendor bundle, the reviewed Hearth mapping file, and the validation rules a clean checkout must satisfy offline.

Hearth is a tracking and automation tool. The catalog is not medical advice.

## Pin and waiver

The pinned upstream is [bryllim/workout-guide](https://github.com/bryllim/workout-guide) release tag `v1.0.0`.

That release contains PNG frames and no SVG frames. The product requirement is the ordered three-frame animation, not a specific frame format. Hearth therefore vendors the release PNG frames and keeps the explicit release-tag requirement. A branch name or unreleased commit is not an acceptable pin.

`bin/sync-workout-guide` is a developer command. Application runtime does not request GitHub.

## Vendor bundle

A clean checkout must contain every file required for an offline import under `vendor/workout_guide/`:

| Path | Role |
| --- | --- |
| `manifest.json` | Source records and frame metadata |
| `assets/<slug>/frame-{1,2,3}.png` | Ordered animation frames |
| `LICENSE-ASSETS` | CC BY-SA 4.0 asset license, beside the frames |
| `ATTRIBUTION.md` | Upstream attribution, beside the frames |
| `VERSION` | Repository, release tag, and the commit SHA the tag resolved to at sync time |
| `CHECKSUMS` | SHA-256 digest of every regular file in the bundle except `CHECKSUMS` itself |

`CHECKSUMS` covers `VERSION`. The sync command writes `VERSION` first and `CHECKSUMS` last so the `VERSION` digest is stable.

The bundle must not contain `.svg` files, `package.json`, `package-lock.json`, `node_modules`, `.mjs`, or `.ts`.

## Record contract

Every manifest record has a closed key set: `id`, `slug`, `name`, `exerciseType`, `equipment`, `primaryMuscle`, `secondaryMuscles`, `isStretch`, `frames`, and `attribution`.

General invariants, independent of the current pin:

- `id`, `slug`, and `name` are non-empty
- `id` is unique across records
- `slug` is unique across records
- every record has a non-empty `frames` list
- frame `index` values form a contiguous ascending sequence starting at `1`
- every frame `path` is relative, contains no `..`, resolves inside `vendor/workout_guide/`, exists, and is non-empty
- every record carries `creator`, `creatorUrl`, `license`, and `licenseUrl`
- every frame source block that exists carries `name`, `url`, `license`, `licenseUrl`, and `changes`

Pinned-release assertions for `v1.0.0`:

- exactly 302 records
- exactly three frames per record
- every frame reports format `png` and size 512 × 512
- all 906 referenced files exist
- no file under `assets/` is unreferenced

## Mapping contract

`config/workout_guide_overrides.yml` is the reviewed Hearth mapping. It lives outside `vendor/workout_guide/` because a sync deletes destination files that are absent from the staging tree.

Closed top-level keys: `contract_version`, `source`, `exercises`, `muscle_aliases`, `muscle_compounds`, and `muscle_unmapped`.

`exerciseType` and `equipment` cannot determine a movement pattern. Modality and movement pattern are reviewed per source record, keyed by the stable source slug. All 302 records carry an explicit decision. There is no automatic `other` default.

Every exercise entry has `modality` from `Exercise::MODALITIES` and `movement_pattern` from `Exercise::MOVEMENT_PATTERNS`. The exercises key set equals the manifest slug set exactly.

An optional `muscle_targets` list replaces muscle resolution for that slug. Use it when a global mapping is not anatomically valid. A record whose `primaryMuscle` is unmapped must carry this override.

### Muscle names

Every source muscle name appears in exactly one of `muscle_aliases`, `muscle_compounds`, or `muscle_unmapped`. The union of those three key sets equals the manifest muscle-name set exactly.

Of the 23 source names in `v1.0.0`:

- `Cardio` and `Mobility` are unmapped non-anatomical labels and resolve to zero targets
- `Back`, `Core`, `Grip`, `Hips`, `Legs`, `Lower Back`, `Posterior Chain`, and `Upper Back` are compounds
- the remaining names are one-to-one aliases

A compound entry supplies both `as_primary` and `as_secondary`. Each list is non-empty. No role is computed; every role is written down. Roles are limited to `primary`, `secondary`, and `stabilizer`.

A muscle key must not repeat inside one expansion list or one slug-level override.

### Role precedence

When several source mappings produce the same `muscle_key`, keep one target at the strongest role, ordered `primary` > `secondary` > `stabilizer`.

`sumo-deadlift` is the pinned overlapping record: `Posterior Chain` as primary expands `glutes` to `primary`, and `Glutes` as a secondary aliases `glutes` to `secondary`. The merge keeps `primary`.

### Primary muscle requirement

After aliases, compounds, unmapped names, slug-level overrides, and role-precedence merge, every record has at least one target with role `primary`.

This ticket validates structure, completeness, closed vocabularies, and role legality. It does not require a `muscle_key` to name a persisted `Muscle` row.

## Duplicate-key rejection

`YAML.safe_load` keeps the last duplicate mapping key. Validation therefore walks the `Psych.parse` syntax tree before hash conversion and rejects any Mapping whose scalar keys repeat.

## Update process

```bash
bin/sync-workout-guide v1.0.0
```

The command requires an explicit GitHub release tag. It rejects a branch name and a bare commit SHA. It downloads the release archive, copies `manifest.json`, PNG frames, `LICENSE-ASSETS`, and `ATTRIBUTION.md` through a filtered staging tree, then synchronizes `vendor/workout_guide/` with deletion and content comparison. Equal size and modification time are not enough to keep a destination file. `VERSION` and `CHECKSUMS` are excluded from that copy so they survive and are rewritten after the sync. `CHECKSUMS` path order is `LC_ALL=C` sort.

A later change to the copy rules must be re-proved by placing a stale destination file, including a stale `.svg`, and confirming the sync removes it.

After a sync of an already-current pin, the command prints `no source changes`.

## Source snapshot and merge results

Runtime import belongs to a later ticket. That importer must call `Exercise.merge_source_record!` and `Exercise.mark_sources_removed!`. This ticket defines the snapshot shape and the shared result vocabulary those callers use.

`exercises.source_snapshot` is the three-way merge base. It is one JSON object with these keys:

| Key | Shape |
| --- | --- |
| `scalars` | `{ name, modality, movement_pattern, equipment }` |
| `targets` | `{ <muscle_key>: <role> }` |
| `removed_target_keys` | `[ <muscle_key> ]` |
| `visuals` | `{ <visual_source_key>: { alt_text, caption, frame_interval_ms, items: [ { source_identifier, source_checksum, content_digest } ] } }` |
| `removed_visual_keys` | `[ <visual_source_key> ]` — household deletion tombstones only |
| `attribution` | `{ creator, creator_url, license, license_url, source_name, source_url, change_note }` |

`content_digest` is the Active Storage blob checksum of the attached file. `source_checksum` is upstream provenance and is not evidence of the current attachment.

Result values from `Exercise::SourceMerge::Result`:

| Status | Meaning |
| --- | --- |
| `created` | No exercise with that source key existed, and the merge created one. |
| `updated` | At least one source-driven scalar, target, visual item, attribution value, source version, or removal state changed. A source version change alone is `updated`. A name conflict plus any other applied change is `updated` with reason `name_conflict`. |
| `preserved` | No source-driven change applied. `preserved` carries reason `name_conflict` only when a name conflict exists and nothing else changed. |
| `skipped` | A household exercise already holds the source name and no exercise holds the source key. |
| `source_removed` | The sweep set or retained `source_removed_at`. |
| `failed` | Validation or mapping failed and this record's transaction rolled back. |

Guidance is never imported. `exercise_visuals.provenance_status` is content provenance and is not merge state.

## License boundary

Frame assets are licensed CC BY-SA 4.0. That license is separate from Hearth's O'Saasy license. Keep `LICENSE-ASSETS` and `ATTRIBUTION.md` beside the frames when the bundle is copied or redistributed.
