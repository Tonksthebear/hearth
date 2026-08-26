# Plan — Build exercise visual playback and the muscle map

Ticket: `ticket_1787683377_217672`
Run: `run_1787764348_813657`
Step: `hotwire_plan`

## 1. Context loaded

### Role playbooks
- `~/knowledge/notes/planner-playbook.md`
- `~/knowledge/notes/hotwire-app-planner-playbook.md`

### Vault conventions and gotchas that constrain this ticket
- `hearth ui pipeline context must route elements conventions`
- `hearth uses tailwindplus elements as its default ui system`
- `yass-and-elements-yml-drive-all-component-styling`
- `use-icon-helper-instead-of-raw-svgs-in-elements`
- `styles and html live in html not javascript`
- `hearth exercise visuals serve video inline and svg as a download`
- `an upstream source checksum is not evidence of current attachment content`
- `hearth provenance status is content provenance never source identity`
- `hearth preview order must read persisted muscle display positions`
- `hearth exercise visual fixtures stay empty because visuals are assembled in tests`
- `hearth controller and integration tests need a tailwind build not only system tests`
- `hearth parallel system tests flake so a serial run is the regression oracle`
- `a hearth change to config ci rb obliges a bin ci run`
- `hearth nested row authoring uses server owned named buttons instead of stimulus cloning`

### Repository code read
- `AGENTS.md`, `config/routes.rb`, `config/ci.rb`, `config/muscles.yml`, `config/elements.yml`
- `app/models/exercise.rb`, `app/models/exercise/source_merge.rb`, `app/models/muscle.rb`,
  `app/models/exercise_muscle_target.rb`, `app/models/exercise_visual.rb`,
  `app/models/exercise_visual_item.rb`, `app/models/activity_library.rb`
- `app/models/workout_guide/import.rb`, `app/models/workout_guide/muscle_mapping.rb`,
  `vendor/workout_guide/manifest.json`
- `app/controllers/exercises_controller.rb`
- `app/views/exercises/show.html.erb`, `_visual.html.erb`, `_visuals.html.erb`, `_muscle_targets.html.erb`
- `app/javascript/controllers/frame_sequence_controller.js`
- `app/views/layouts/application.html.erb`
- `test/application_system_test_case.rb`, `test/test_helpers/exercise_visual_test_helper.rb`,
  `test/system/exercises_and_workout_templates_test.rb`,
  `test/system/household_people_and_account_test.rb`, `test/fixtures/exercise_visuals.yml`
- `db/schema.rb` (`exercises`, `exercise_visuals`, `exercise_visual_items`, `muscles`, `exercise_muscle_targets`)

### Dependency tickets (all closed and merged into `origin/main`)
- `ticket_1787683366_868680` — muscle taxonomy and exercise target model.
- `ticket_1787683370_874091` — flexible exercise visuals and ordered frame sequences.
- `ticket_1787683375_195812` — Workout Guide import.

### Branch state
This worktree branch started behind `origin/main` and did not contain the dependency work.
`git merge origin/main` brought all three dependency tickets into the branch. The plan is written
against the merged tree.

### What already exists (do not rebuild)
- `Muscle` with 19 seeded keys, `display_position`, aliases, and `Muscle.displayed`.
- `ExerciseMuscleTarget` with `primary`, `secondary`, `stabilizer` roles and `in_display_order`.
- `Exercise#ordered_muscle_targets`, `Exercise#source_attribution`, `Exercise#source_snapshot`.
- `ExerciseVisual` kinds `image`, `frame_sequence`, `video`, with `frame_interval_ms` persisted and
  constrained to 100..5000, plus `alt_text`, `caption`, `display_attribution`, `provenance_status`.
- `ExerciseVisualItem#inline_renderable?` already excludes SVG and video.
- `app/views/exercises/_visual.html.erb` already renders image, video, frame-sequence, and SVG
  download links.
- `app/javascript/controllers/frame_sequence_controller.js` already auto-advances frames and reads
  `data-frame-sequence-interval-value`.
- The Workout Guide import creates one `frame_sequence` visual per exercise with three PNG frames and
  writes attribution into `exercises.source_snapshot["attribution"]`.

### What is missing (this ticket)
- Any muscle map. No SVG body art exists in the repository.
- Any muscle target rendering on the exercise detail page.
- Any attribution rendering on the exercise detail page.
- Player controls. Playback is autoplay-only and cannot be paused, stepped, or keyboard-driven.
- Any reduced-motion handling anywhere in the app.
- Any dark surface for the white monochrome Workout Guide PNG art.

## 2. Scope and non-scope

### Scope
All changes land on the exercise detail experience (`exercises#show`) and its supporting model layer.

1. **Muscle map source of truth.** Add `MuscleMap`, a plain Ruby object in `app/models/`, following the
   existing `ActivityLibrary` PORO precedent. It owns:
   - `FRONT_REGIONS` and `BACK_REGIONS` — ordered maps of muscle key to SVG path geometry.
   - `UNMAPPED_KEYS` — the explicit allowlist of seeded muscle keys with no region on the first map,
     each with a stated reason.
   - `MuscleMap.covered_keys` — union of both region maps.
   - An instance built from an exercise, exposing per-region role (`primary`, `secondary`,
     `stabilizer`, or none) and the ordered text target list.
   The view iterates the same region maps that the coverage test asserts against, so one authority
   drives rendering and verification.
2. **Front and back SVG body map partial.** Add `app/views/exercises/_muscle_map.html.erb`. Each drawn
   region is a `<path>` carrying a stable `data-muscle-key` and a server-rendered `data-role`.
   Tailwind `data-[role=...]` variants supply the highlight colors. No JavaScript participates.
3. **Accessible text target list.** Add `app/views/exercises/_muscle_targets_list.html.erb` rendering
   every target grouped by role, ordered by persisted `muscles.display_position`. The SVG is
   `aria-hidden`; the list carries the information.
4. **Frame player controls.** Extend `app/javascript/controllers/frame_sequence_controller.js` with
   `play`, `pause`, `previous`, and `next` actions, and add server-rendered buttons in
   `_visual.html.erb`. State is expressed only through `data-playing` and `aria-pressed` /
   `aria-label`. The controller never touches `classList` or inline styles.
5. **Reduced motion.** The controller reads `window.matchMedia("(prefers-reduced-motion: reduce)")` on
   connect and starts paused when it matches. The timer still clears on `disconnect`.
6. **Dark surface for unchanged Workout Guide art.** Add `ExerciseVisual#unmodified_source_art?`,
   which is true when `source_key` is in the `workout_guide:` namespace and every item's current
   `file.blob.checksum` still equals the `content_digest` recorded in
   `exercise.source_snapshot["visuals"][source_key]["items"]`. The view maps that predicate to a dark
   backdrop utility so white-on-transparent PNG art stays visible in light mode.
7. **Attribution.** Render `Exercise#source_attribution` (creator, creator URL, license, license URL,
   source name, source URL, change note) as a section on the detail page, alongside the already
   rendered per-visual `caption` and `display_attribution`.
8. **Controller preparation.** `ExercisesController#show` builds the `MuscleMap` and eager-loads
   `exercise_muscle_targets: :muscle`. The view renders only.
9. **Tests.** Model, controller, and system coverage as listed in section 6.

### Non-scope
- No schema migration. Every needed column already exists.
- No change to `config/muscles.yml`, `Muscle::DEFAULTS`, or the seeded muscle vocabulary.
- No change to the exercise form, the nested authoring flow, or `WorkoutGuide::Import`.
- No change to `Exercise::SourceMerge` merge semantics.
- No change to `db/seeds.rb` or `config/ci.rb`. The `bin/ci` demo assertion pins
  `exercises: 5`, `active_storage_blobs: 2`, and `active_storage_attachments: 2`; this plan adds no
  seeded rows, so those counts stay valid and no `bin/ci` obligation is created.
- No muscle map on `exercises#index`, the activity library, workout templates, or training sessions.
- No recoloring, transform, or variant processing of any uploaded or vendored image.
- No new Elements composite component and no new `config/elements.yml` axis.

## 3. Assumptions and unknowns

### Assumptions (stated, not verified with a human)
- **A1. "Unchanged" means the household has not replaced the file.** The plan detects it by comparing
  the live `file.blob.checksum` against the snapshot `content_digest`, never against
  `exercise_visual_items.source_checksum`. The vault gotcha
  `an upstream source checksum is not evidence of current attachment content` states that
  `source_checksum` records incoming provenance and is not recalculated after a household replacement.
  A household that uploads its own frames therefore gets the default surface, not the dark one.
- **A2. The map is per-exercise.** "the accessible exercise detail experience" scopes the map to
  `exercises#show`. No weekly or household coverage view is built.
- **A3. Front and back are two side-by-side SVGs on one page**, not a toggle or a tabbed control. This
  keeps every region reachable without JavaScript and satisfies "All controls work by keyboard"
  without adding a control.
- **A4. The body map is hand-authored inline ERB, not a `rails_icons` asset.** The convention
  `use-icon-helper-instead-of-raw-svgs-in-elements` governs icons inside the Elements component lane.
  A body map is not an icon: each region must carry a server-rendered `data-muscle-key` and
  `data-role`, which the icon helper cannot express. This is a documented deviation for Plan Review to
  confirm or reject.
- **A5. Player control buttons reuse the existing `btn` axis** through `yass(btn: ...)` /
  `class: { btn: [...] }`, matching `exercises/show.html.erb` and `exercises/_visuals.html.erb`. No new
  Elements preview source is required because no new composite is introduced.
- **A6. Highlight colors come from Tailwind `data-[role=...]` variants** written in the ERB, with
  explicit `dark:` counterparts. No color is defined in JavaScript.

### Unknowns for Plan Review or the Implementer
- **U1.** Which muscle keys land in `UNMAPPED_KEYS`. The 19 seeded keys are `trapezius`, `shoulders`,
  `rear_delts`, `chest`, `rhomboids`, `lats`, `biceps`, `triceps`, `forearms`, `rectus_abdominis`,
  `obliques`, `erector_spinae`, `hip_flexors`, `groin`, `adductors`, `glutes`, `quadriceps`,
  `hamstrings`, `calves`. `hip_flexors` and `groin` are deep or internal and are the expected
  allowlist candidates. The Implementer settles this while drawing. The invariant, not the list, is
  the contract: every seeded key is either drawn or allowlisted with a reason.
- **U2.** Whether a frame sequence with exactly one inline-renderable item should still show controls.
  `ExerciseVisual` requires at least two items for `frame_sequence`, but one item can be an SVG
  download. The plan renders controls only when two or more animated items exist, matching the
  existing `frame_sequence_controller.js` guard.
- **U3.** Whether `tmp/tailwindplus_elements_previews` must be populated for this ticket. The
  directory is absent in this worktree. This plan introduces no new Elements composite, so no preview
  source is needed. If Plan Review disagrees, the Implementer must restore that directory before
  writing control markup.

## 4. Affected surfaces and files

### New
| Path | Layer | Purpose |
|---|---|---|
| `app/models/muscle_map.rb` | PORO | Region geometry, allowlist, per-exercise role resolution |
| `app/views/exercises/_muscle_map.html.erb` | View | Front and back SVG regions with `data-muscle-key` and `data-role` |
| `app/views/exercises/_muscle_targets_list.html.erb` | View | Accessible role-grouped target list |
| `app/views/exercises/_attribution.html.erb` | View | Source and asset attribution |
| `test/models/muscle_map_test.rb` | Test | Coverage invariant, ordering, role resolution |
| `test/system/exercise_visual_playback_test.rb` | Test | Browser evidence for playback, controls, modes |

### Changed
| Path | Change |
|---|---|
| `app/controllers/exercises_controller.rb` | `show` builds `@muscle_map` and eager-loads `exercise_muscle_targets: :muscle` |
| `app/views/exercises/show.html.erb` | Render muscle map, target list, and attribution sections |
| `app/views/exercises/_visual.html.erb` | Player controls, `data-playing` state, dark surface for unchanged source art |
| `app/javascript/controllers/frame_sequence_controller.js` | `play`, `pause`, `previous`, `next`, reduced-motion start state, timer clearing |
| `app/models/exercise_visual.rb` | `unmodified_source_art?` predicate |
| `test/models/exercise_visual_test.rb` | Cover the new predicate in both states |
| `test/controllers/exercises_controller_test.rb` | Cover render output for each visual kind and SVG safety |

No migration. No route change. No `config/` change.

## 5. Risks

| # | Risk | Mitigation |
|---|---|---|
| R1 | The body-map geometry is hand-authored art and can drift from the region key list. | The partial iterates `MuscleMap::FRONT_REGIONS` / `BACK_REGIONS`; the coverage test asserts against the same constants, so a drawn region cannot exist outside the tested set. |
| R2 | The dark-surface predicate reads `file.blob.checksum` per item on every detail render. | `ExercisesController#show` already eager-loads `exercise_visuals: { exercise_visual_items: { file_attachment: :blob } }`. The checksum is a persisted column on the loaded blob, so no extra query and no file read occurs. |
| R3 | Uploaded SVG could be rendered inline while adding map markup. | `ExerciseVisualItem#inline_renderable?` already excludes SVG. A controller test asserts an uploaded SVG produces an anchor and never an `img` or inline `<svg>` from blob content. |
| R4 | Stimulus could be tempted to mutate classes for playing or highlight state. | The controller only toggles `data-*` and ARIA attributes; Tailwind `data-[...]` variants own presentation. A system test asserts the class attribute is unchanged between playing and paused. |
| R5 | Parallel system tests flake in Hearth and can look like a ticket regression. | Classify with a serial `PARALLEL_WORKERS=1` full run, or matched base and head arms at the same seed, process count, browser, and driver. |
| R6 | A fresh pipeline worktree has an empty `app/assets/builds`, so layout-rendering Rails tests fail with a missing `tailwind.css`. | Run `bin/rails tailwindcss:build` before every Rails test command, not only before system tests. |
| R7 | Adding visual fixtures would break catalog destroy constraints. | Keep `test/fixtures/exercise_visuals.yml` and `exercise_visual_items.yml` empty. Assemble visuals through `ExerciseVisualTestHelper`. |
| R8 | Reading `Muscle::DEFAULTS` for display order would produce wrong output after a household order change. | The target list and `MuscleMap` order from persisted `muscles.display_position` through `Exercise#ordered_muscle_targets`. |
| R9 | The white monochrome PNG art is invisible in light mode if the dark surface is missed. | A system test emulates `prefers-color-scheme: light` and asserts the frame container's computed background is dark for a Workout Guide sourced visual. |
| R10 | This branch was behind `origin/main` and the dependency work was absent. | Already resolved by merging `origin/main` into the ticket branch before planning. The Implementer must not re-derive dependency code. |

## 6. Acceptance checks and tests

### Traceability to the ticket's acceptance criteria
| Ticket criterion | Proof |
|---|---|
| Every seeded Muscle key has a map region or appears in the explicit allowlist | `test/models/muscle_map_test.rb`: `Muscle::KEYS - MuscleMap.covered_keys - MuscleMap::UNMAPPED_KEYS` is empty, and the two sets do not overlap |
| The three Workout Guide frames cycle as one animation | System test on an imported Workout Guide exercise: three frame targets in one container, one visible at a time, index advances |
| Playback timing comes from the visual data attribute, not a JavaScript constant | Controller test asserts `data-frame-sequence-interval-value` equals the record's `frame_interval_ms`; system test sets a non-default interval and observes the changed cadence |
| The player clears timers during Turbo disconnect | System test navigates away with Turbo and back, then asserts a single advancing sequence and no double-speed cycling |
| Reduced-motion users start with playback paused | System test emulates `prefers-reduced-motion: reduce` through `Emulation.setEmulatedMedia`, asserts `data-playing` is absent and the frame index does not change over an interval |
| All controls work by keyboard | System test tabs to each control and activates it with the keyboard, asserting frame changes and `data-playing` transitions |
| The muscle list conveys all information without the SVG | Controller test asserts every target name and role appears in the rendered list; system test asserts the SVG carries `aria-hidden="true"` and the list does not |
| System tests cover each visual kind, controls, attribution, SVG safety, and light and dark modes | `test/system/exercise_visual_playback_test.rb` covers image, video, frame sequence, SVG download, attribution text, and both emulated color schemes |

### Commands
Run `bin/rails tailwindcss:build` first, in this worktree, before any Rails test command.

```
bin/rails tailwindcss:build
bin/rails test test/models/muscle_map_test.rb test/models/exercise_visual_test.rb test/controllers/exercises_controller_test.rb
bin/system-test-browser bin/rails test test/system/exercise_visual_playback_test.rb
bin/system-test-browser bin/rails test test/system/exercises_and_workout_templates_test.rb
PARALLEL_WORKERS=1 bin/system-test-browser bin/rails test:system
bin/rubocop
bin/brakeman --quiet --no-pager --exit-on-warn --exit-on-error
```

The serial `test:system` run is the regression oracle. Do not classify a parallel failure as a
regression without it, or without matched base and head arms.

### Runtime path proof
The production entry point is `GET /exercises/:id` served by `ExercisesController#show`. Every new
surface renders from that action:
- `@muscle_map` is built in `show` and rendered by `exercises/show.html.erb`.
- The player controls render inside `exercises/_visual.html.erb`, which `show.html.erb` already calls
  for every persisted visual.
- The system tests reach the page by navigating Activities to Library to All exercises to the
  exercise, matching the real user path already used by
  `test/system/exercises_and_workout_templates_test.rb`.
This ticket is not scaffold-only.

## 7. Vault gaps worth capturing

1. **Muscle map region authority.** Whether region geometry belongs in a PORO constant, a config file,
   or an asset is not settled in the vault. The chosen rule — the view iterates the same constants the
   coverage test asserts against — is a durable Hearth convention if Plan Review accepts it.
2. **Body art is not an icon.** `use-icon-helper-instead-of-raw-svgs-in-elements` reads as an absolute
   rule. A note recording the data-bearing SVG exception would stop this question recurring on every
   diagram, chart, or map ticket.
3. **Reduced motion has no Hearth convention.** The app has no `prefers-reduced-motion` handling and no
   vault note. The rule that a Stimulus controller reads the media query while CSS owns presentation
   is worth capturing once the implementation lands.
4. **Emulated media in system tests.** `Emulation.setEmulatedMedia` appears only in
   `household_people_and_account_test.rb`. A note naming it as the Hearth technique for both
   `prefers-color-scheme` and `prefers-reduced-motion`, including the `ensure` reset, would make it
   discoverable.
5. **Monochrome source art needs a surface, not a transform.** The rule that Hearth solves white
   vendored art with a backdrop rather than an Active Storage transform reinforces
   `hearth exercise visuals serve video inline and svg as a download` and is worth its own note.
