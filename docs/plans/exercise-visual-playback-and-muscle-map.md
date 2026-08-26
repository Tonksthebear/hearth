# Plan — Build exercise visual playback and the muscle map

Ticket: `ticket_1787683377_217672`
Run: `run_1787764348_813657`
Step: `hotwire_plan` (revision 2, after Plan Review `review_1787767470_929261`)

## 0. Response to Plan Review

| Finding | Severity | Resolution |
|---|---|---|
| The plan does not use the required Elements source | blocking | **Resolved by human waiver.** Question `question_1787767588_352168` answered option A: an explicit preview-path waiver for this ticket and run. Do not require or create `tmp/tailwindplus_elements_previews`. The authoritative Elements source is `app/components/elements`, `config/elements.yml`, `lib/tailwindplus_elements_components`, the vendored Elements JavaScript, and the existing exercise views. Frame controls reuse the existing `yass(btn: ...)` axis. No new form-control or button classes are added. See section 3, E1. |
| The plan leaves the muscle map policy unresolved | blocking | **Resolved by human answer.** Question `question_1787767327_580552`: draw both `hip_flexors` and `groin` on the first anterior map; neither goes in the allowlist. `MuscleMap::UNMAPPED_KEYS` ships as an empty frozen constant so the ticket's allowlist mechanism and its invariant test both exist. See section 3, D1. |
| SVG geometry is assigned to the wrong layer | blocking | **Fixed.** All path geometry moves into the view layer. `app/views/exercises/_muscle_map.html.erb` holds the literal `<svg>` and `<path>` markup. The `MuscleMap` PORO keeps only role resolution and the allowlist and holds no geometry. The coverage invariant is now proven by rendering the partial and reading the emitted `data-muscle-key` values, which is stronger than comparing two constants. See section 3, D2. |
| The player contract and acceptance checks need precise state rules | major | **Fixed.** Section 4 states the complete attribute vocabulary, the eight lifecycle rules, and the runtime assertions that prove each one. |
| The plan omits required stack context and durable artifact linkage | major | **Fixed.** Section 1 now names the stack packet and the project overlay required by `hotwire-app-planner-playbook`. The plan artifact carries its committed path and commit SHA in its payload. |

## 1. Context loaded

### Stack packet
**Rails plus Hotwire**, with the Hearth Elements overlay. This ticket changes models, a controller, ERB
views, and one Stimulus controller. Browser behavior is part of the deliverable, so `rack_test` cannot
prove it.

### Project overlay
`hearth-overview` — specifically its "Workout Guide and Exercise Visuals" and "User Interface" sections.

### Role playbooks
- `~/knowledge/notes/planner-playbook.md`
- `~/knowledge/notes/hotwire-app-planner-playbook.md`

### Elements packet
- `hearth ui pipeline context must route elements conventions`
- `hearth uses tailwindplus elements as its default ui system`
- `yass-and-elements-yml-drive-all-component-styling`
- `use-icon-helper-instead-of-raw-svgs-in-elements`
- `tailwindplus elements previews are full implementation sources not layout references`
- `plan agents must verify filesystem state before overriding vault path notes`

### Hearth domain conventions and gotchas
- `styles and html live in html not javascript`
- `controllers prepare data views render only`
- `fat models over service objects`
- `hearth exercise visuals serve video inline and svg as a download`
- `forbidden active storage transforms need raising guards on attachment and blob`
- `an upstream source checksum is not evidence of current attachment content`
- `hearth catalog source merge keeps its three way base on the record`
- `hearth provenance status is content provenance never source identity`
- `hearth preview order must read persisted muscle display positions`
- `loaded association ordering helpers must sort in memory`
- `query count guards must call the production entry point`
- `hearth exercise visual fixtures stay empty because visuals are assembled in tests`
- `hearth controller and integration tests need a tailwind build not only system tests`
- `hearth parallel system tests flake so a serial run is the regression oracle`
- `a hearth change to config ci rb obliges a bin ci run`

### Repository code read
- `AGENTS.md`, `config/routes.rb`, `config/ci.rb`, `config/muscles.yml`, `config/elements.yml`,
  `config/importmap.rb`, `config/initializers/tailwindplus_elements_components.rb`
- `app/models/exercise.rb`, `app/models/exercise/source_merge.rb`, `app/models/muscle.rb`,
  `app/models/exercise_muscle_target.rb`, `app/models/exercise_visual.rb`,
  `app/models/exercise_visual_item.rb`, `app/models/activity_library.rb`
- `app/models/workout_guide/{import,muscle_mapping}.rb`, `vendor/workout_guide/manifest.json`
- `app/controllers/exercises_controller.rb`
- `app/views/exercises/{show,_visual,_visuals,_muscle_targets}.html.erb`,
  `app/views/layouts/application.html.erb`
- `app/javascript/controllers/frame_sequence_controller.js`
- `app/components/elements/` (22 entries), `lib/tailwindplus_elements_components/`
- `test/application_system_test_case.rb`, `test/test_helpers/exercise_visual_test_helper.rb`,
  `test/integration/exercise_visual_rendering_test.rb`,
  `test/system/{exercises_and_workout_templates,household_people_and_account}_test.rb`,
  `test/fixtures/exercise_visuals.yml`, `db/schema.rb`

### Branch state
This worktree branch started behind `origin/main` and contained none of the three closed dependency
tickets. `git merge origin/main` brought them in with no conflicts. The plan is written against the
merged tree, not a stale one.

### What already exists — do not rebuild
- `Muscle` with 19 seeded keys, `display_position`, aliases, `Muscle.displayed`, `Muscle::KEYS`.
- `ExerciseMuscleTarget` with `primary`, `secondary`, `stabilizer`, and `in_display_order`.
- `Exercise#ordered_muscle_targets` (sorts loaded targets in memory by persisted `display_position`),
  `Exercise#source_attribution`, `Exercise#source_snapshot`.
- `ExerciseVisual` kinds `image`, `frame_sequence`, `video`; `frame_interval_ms` persisted and
  constrained to 100..5000; `alt_text`, `caption`, `display_attribution`, `provenance_status`.
- `ExerciseVisualItem#inline_renderable?` already excludes SVG and video.
- `exercises/_visual.html.erb` already renders image, video, frame sequence, and SVG download links.
- `frame_sequence_controller.js` already auto-advances and already reads
  `data-frame-sequence-interval-value`.
- `test/integration/exercise_visual_rendering_test.rb` already prepends a six-combination transform
  guard to `ActiveStorage::Attachment` and `ActiveStorage::Blob`, already drives the production entry
  point `get exercise_path(exercise)`, and already asserts inline video and attachment SVG disposition.

### What is missing — this ticket
- Any muscle map. No body art exists in the repository.
- Any muscle target or attribution rendering on the exercise detail page.
- Player controls. Playback is autoplay-only: no pause, no stepping, no keyboard path.
- Any `prefers-reduced-motion` handling anywhere in the app.
- Any dark surface for the white monochrome Workout Guide PNG art.

## 2. Scope and non-scope

### Scope
Every change lands on the exercise detail experience (`exercises#show`) and its supporting layers.

1. `app/models/muscle_map.rb` — a PORO following the `ActivityLibrary` precedent. It owns
   `UNMAPPED_KEYS` (empty) and role resolution. It holds no geometry and no presentation.
2. `app/views/exercises/_muscle_map.html.erb` — literal front and back `<svg>` markup. Every region is
   a `<path>` carrying its own `d` geometry, a stable `data-muscle-key`, and a server-rendered
   `data-role`. Tailwind `data-[role=...]` variants supply highlight colors, with `dark:` counterparts.
3. `app/views/exercises/_muscle_targets_list.html.erb` — the accessible role-grouped text list, ordered
   by persisted `muscles.display_position`.
4. `app/views/exercises/_attribution.html.erb` — `Exercise#source_attribution` fields.
5. `app/javascript/controllers/frame_sequence_controller.js` — `play`, `pause`, `previous`, `next`,
   reduced-motion start state, and timer clearing, under the contract in section 4.
6. `app/views/exercises/_visual.html.erb` — four server-rendered control buttons using the existing
   `yass(btn: ...)` axis, plus the dark surface for unchanged Workout Guide art.
7. `app/models/exercise_visual.rb` — `unmodified_source_art?`.
8. `app/controllers/exercises_controller.rb` — `show` builds `@muscle_map` and adds
   `exercise_muscle_targets: :muscle` to the existing eager load. The view renders only.
9. Tests as listed in section 6.

### Non-scope
- No migration. Every needed column exists.
- No change to `config/muscles.yml`, `Muscle::DEFAULTS`, or the seeded vocabulary.
- No change to the exercise form, nested authoring, or `WorkoutGuide::Import`.
- No change to `Exercise::SourceMerge` merge semantics.
- No change to `db/seeds.rb` or `config/ci.rb`. The release-gate demo assertion pins `exercises: 5`,
  `active_storage_blobs: 2`, and `active_storage_attachments: 2`; this plan adds no seeded rows, so
  those counts stay valid and no `bin/ci` obligation is created.
- No new Elements composite, no new `config/elements.yml` axis, and no new button or form-control
  classes. The human waiver explicitly forbids adding them where the existing source covers the control.
- No muscle map on `exercises#index`, the activity library, workout templates, or training sessions.
- No recoloring, variant, preview, or representation call on any image. The existing transform guard
  must keep passing.
- No new transform-guard test file. The existing integration test is extended instead.

## 3. Assumptions, resolved decisions, and unknowns

### Resolved by human answer
- **E1 — Elements source.** `question_1787767588_352168`, option A. An explicit preview-path waiver for
  this ticket and run. `tmp/tailwindplus_elements_previews` must not be required or created. The
  authoritative source is `app/components/elements`, `config/elements.yml`,
  `lib/tailwindplus_elements_components`, the vendored Elements JavaScript, and existing exercise views.
  Frame controls reuse `yass(btn: ...)`. The app-owned data-bearing SVG body map needs no Elements
  composite. Plan Review and Verify must treat this source decision as satisfied.
  Filesystem evidence supporting the question: `ls tmp/` shows only `.keep`, `pids/`, `storage/`;
  `git log --all -- tmp/tailwindplus_elements_previews` is empty; `git log --all --diff-filter=A
  -- 'tmp/*'` returns only the initial commit; no rake task, `bin/` script, or initializer produces the
  path; a repo-wide grep matched only this plan document.
- **D1 — Muscle map policy.** `question_1787767327_580552`. Draw both `hip_flexors` and `groin` on the
  first anterior map. Neither key goes in the allowlist. Use distinct regions with
  `data-muscle-key="hip_flexors"` and `data-muscle-key="groin"`. Bilateral shapes may share one stable
  key. Keep hit and highlight regions visually distinct where the anatomy overlaps. The accessible text
  target list remains the authoritative fallback.
  Consequence: all 19 seeded keys are drawn. `MuscleMap::UNMAPPED_KEYS` ships as `[].freeze`. The
  ticket requires the allowlist mechanism, so the constant and its invariant test both exist and stay
  ready for a future key that cannot be drawn.

### Design decisions
- **D2 — Geometry lives in the view, and the invariant is proven by rendering.**
  `_muscle_map.html.erb` contains the literal `<svg>` and every `<path d="...">`. The `MuscleMap` PORO
  exposes only `role_for(muscle_key)`, the ordered text targets, and `UNMAPPED_KEYS`. Each region is
  emitted as `tag.path d: "...", "data-muscle-key": "chest", "data-role": muscle_map.role_for("chest")`.
  The coverage test renders the partial and parses the emitted `data-muscle-key` values, then asserts
  `Muscle::KEYS - rendered_keys - MuscleMap::UNMAPPED_KEYS` is empty and that no rendered key is
  outside `Muscle::KEYS`. This removes the previous model-layer geometry constant and proves the real
  markup, not a parallel list.
- **D3 — Unchanged means the household has not replaced the file.**
  `ExerciseVisual#unmodified_source_art?` is true when `source_key` is in the `workout_guide:`
  namespace and, for every item, `item.file.blob.checksum` equals the `content_digest` recorded at
  `exercise.source_snapshot["visuals"][source_key]["items"]` for that `source_identifier`. It never
  reads `exercise_visual_items.source_checksum`, which records incoming provenance and is never
  recalculated after a household replacement. A household that uploads its own frames gets the default
  surface.
- **D4 — The map is per-exercise.** The ticket scopes it to the exercise detail experience. No weekly
  or household coverage view is built.
- **D5 — Front and back render as two SVGs on one page**, not a toggle, so every region is reachable
  without adding a control and without JavaScript.
- **D6 — The body map is hand-authored inline ERB, not a `rails_icons` asset.** Each region must carry
  a server-rendered `data-muscle-key` and `data-role`; `icon()` cannot express per-region data
  attributes. The human waiver in E1 confirms the app-owned data-bearing SVG needs no Elements
  composite. This is the one documented deviation from
  `use-icon-helper-instead-of-raw-svgs-in-elements`.
- **D7 — Highlight colors are Tailwind `data-[role=...]` variants** written in the ERB with explicit
  `dark:` counterparts. No color is defined in JavaScript.

### Remaining unknowns
- **U1 — Frame sequences with fewer than two inline-renderable items.** `ExerciseVisual` requires at
  least two items for `frame_sequence`, but an item may be an SVG download rather than an animated
  frame. The server renders controls only when `visual.animated_items.size >= 2`, and the controller
  keeps its own matching guard. This mirrors the existing `frameTargets.length < 2` early return.
- **U2 — Exact anterior geometry for the overlapping `hip_flexors` and `groin` regions.** The human
  answer requires both to be drawn and visually distinct. The Implementer settles the precise paths
  while drawing; the invariant, not the geometry, is the contract.

## 4. Frame player contract

This section is the precise state specification Plan Review asked for. The Implementer must not
deviate from it without a new plan revision.

### Attribute vocabulary
| Element | Attribute | Rule |
|---|---|---|
| Container `div[data-controller="frame-sequence"]` | `data-frame-sequence-interval-value` | Server-rendered from `visual.frame_interval_ms`. The controller defines no numeric fallback. |
| Container | `data-playing` | Always present and explicit: `"true"` or `"false"`. Never absent-as-false. |
| Container | `role="img"`, `aria-label` | Unchanged. `aria-label` is `visual.alt_text`. |
| Frame `img[data-frame-sequence-target="frame"]` | `data-hidden` | Exactly one frame lacks it; every other frame carries it. Unchanged from the current implementation. |
| Play button | `aria-pressed` | `"true"` while playing, `"false"` while paused. |
| Pause button | `aria-pressed` | `"false"` while playing, `"true"` while paused. |
| All four buttons | `type="button"`, `aria-label` | Stable labels: "Play animation", "Pause animation", "Previous frame", "Next frame". |

Four distinct buttons ship, matching the ticket wording. Play and Pause form a mutually exclusive
toggle group, so `aria-pressed` conveys the current state without a live region. No button is ever
`disabled`, so every control stays keyboard reachable.

### Lifecycle rules
1. `connect()` clears any existing timer before doing anything else.
2. If fewer than two frame targets exist, the controller starts no timer. The server also renders no
   controls in that case.
3. `connect()` reads `window.matchMedia("(prefers-reduced-motion: reduce)")`. When it matches, the
   controller sets `data-playing="false"` and starts no timer. Otherwise it sets `data-playing="true"`
   and starts the timer from `intervalValue`.
4. `disconnect()` clears the timer and nulls the handle. Turbo caches the page before navigation, so
   disconnect must leave no live interval behind.
5. `previous()` and `next()` always pause first — clear the timer and set `data-playing="false"` —
   then step exactly one frame. A step never races an in-flight tick.
6. Stepping wraps in both directions: `next` from the last frame shows the first; `previous` from the
   first frame shows the last.
7. `play()` is a no-op while already playing. `pause()` is a no-op while already paused.
8. The controller never reads or writes `classList`, `style`, or any `class` attribute.

## 5. Affected surfaces and files

### New
| Path | Layer | Purpose |
|---|---|---|
| `app/models/muscle_map.rb` | PORO | `UNMAPPED_KEYS` and role resolution. No geometry. |
| `app/views/exercises/_muscle_map.html.erb` | View | Front and back SVG geometry, `data-muscle-key`, `data-role` |
| `app/views/exercises/_muscle_targets_list.html.erb` | View | Accessible role-grouped target list |
| `app/views/exercises/_attribution.html.erb` | View | Source and asset attribution |
| `test/models/muscle_map_test.rb` | Test | Role resolution, ordering, allowlist shape |
| `test/views/exercises/muscle_map_coverage_test.rb` | Test | Renders the partial; asserts key coverage |
| `test/system/exercise_visual_playback_test.rb` | Test | Browser evidence for playback, controls, modes |

### Changed
| Path | Change |
|---|---|
| `app/controllers/exercises_controller.rb` | `show` builds `@muscle_map`; add `exercise_muscle_targets: :muscle` to the existing eager load |
| `app/views/exercises/show.html.erb` | Render map, target list, and attribution sections |
| `app/views/exercises/_visual.html.erb` | Four control buttons, `data-playing`, dark surface for unchanged source art |
| `app/javascript/controllers/frame_sequence_controller.js` | The section 4 contract |
| `app/models/exercise_visual.rb` | `unmodified_source_art?` |
| `test/models/exercise_visual_test.rb` | Cover the predicate in both states |
| `test/controllers/exercises_controller_test.rb` | Render output per visual kind; query-count guard on the production entry point |
| `test/integration/exercise_visual_rendering_test.rb` | Extend with map and control markup; keep the existing transform guard passing |

No migration. No route change. No `config/` change.

## 6. Risks

| # | Risk | Mitigation |
|---|---|---|
| R1 | Hand-authored geometry drifts from the seeded key vocabulary. | The coverage test renders the real partial and reads emitted `data-muscle-key` values, so a missing or misspelled region fails immediately. There is no second constant to drift from. |
| R2 | `unmodified_source_art?` reads `file.blob.checksum` per item on every detail render. | `show` already eager-loads `exercise_visuals: { exercise_visual_items: { file_attachment: :blob } }`. Checksum is a persisted column on the loaded blob, so no extra query and no file read occurs. The query-count guard calls `get exercise_path(exercise)`, the production entry point, not a hand-built relation. |
| R3 | New markup could route an image through an Active Storage transform. | `test/integration/exercise_visual_rendering_test.rb` already prepends a raising guard for `variant`, `preview`, and `representation` on both `ActiveStorage::Attachment` and `ActiveStorage::Blob` and drives `get exercise_path`. That test must keep passing. |
| R4 | Uploaded SVG could be rendered inline while adding map markup. | `ExerciseVisualItem#inline_renderable?` stays the single view gate. The integration test already asserts attachment disposition for SVG; a controller test asserts the rendered page yields an anchor and no `img` or inline `<svg>` built from blob content. |
| R5 | Stimulus could mutate classes for playing or highlight state. | Section 4 rule 8. A system test captures the container and frame `class` attributes while playing, pauses by keyboard, and asserts the captured values are unchanged. |
| R6 | A leaked interval after Turbo navigation would double playback speed. | Section 4 rule 4, proven by the cadence assertion in section 7. |
| R7 | Hearth parallel system tests flake and can look like a regression. | Classify with a serial `PARALLEL_WORKERS=1` full run, or matched base and head arms at the same seed, process count, browser, and driver. |
| R8 | A fresh pipeline worktree has an empty `app/assets/builds`, so layout-rendering Rails tests fail on a missing `tailwind.css`. | Run `bin/rails tailwindcss:build` before every Rails test command, not only before system tests. |
| R9 | Adding visual fixtures would break catalog destroy constraints. | Keep `test/fixtures/exercise_visuals.yml` and `exercise_visual_items.yml` empty; assemble visuals through `ExerciseVisualTestHelper`. |
| R10 | Reading `Muscle::DEFAULTS` for display order produces wrong output after a household order change. | Order through `Exercise#ordered_muscle_targets`, which sorts loaded targets in memory by persisted `muscles.display_position`. |
| R11 | White monochrome PNG art is invisible in light mode if the dark surface is missed. | A system test emulates `prefers-color-scheme: light` and asserts the frame container's computed background is dark for a Workout Guide sourced visual. |
| R12 | This branch was behind `origin/main` and lacked the dependency work. | Resolved. `origin/main` is merged into the ticket branch. The Implementer must not re-derive dependency code. |

## 7. Acceptance checks and tests

### Traceability to every ticket acceptance criterion
| Ticket criterion | Proof |
|---|---|
| Every seeded Muscle key has a map region or appears in the explicit allowlist | `test/views/exercises/muscle_map_coverage_test.rb` renders `_muscle_map` and asserts `Muscle::KEYS - rendered_keys - MuscleMap::UNMAPPED_KEYS` is empty, that no rendered key is outside `Muscle::KEYS`, and that `hip_flexors` and `groin` are both rendered and absent from the allowlist |
| The three Workout Guide frames cycle as one animation | System test on an imported Workout Guide exercise: three frame targets in one container, exactly one without `data-hidden` at any moment, index advancing |
| Playback timing comes from the visual data attribute, not a JavaScript constant | Controller test asserts `data-frame-sequence-interval-value` equals the record's `frame_interval_ms`; a system test sets `frame_interval_ms` to 1500 and asserts the observed cadence matches, so no JS constant can satisfy both |
| The player clears timers during Turbo disconnect | System test records the visible frame index, Turbo-navigates away and back, then asserts that over a window of three intervals the frame advances exactly three times, not six. It also asserts `data-playing="true"` after return and exactly one `[data-controller="frame-sequence"]` element |
| Reduced-motion users start with playback paused | System test emulates `prefers-reduced-motion: reduce` through `Emulation.setEmulatedMedia`, then asserts `data-playing="false"` and that the same frame still lacks `data-hidden` after three intervals |
| All controls work by keyboard | System test tabs to each of Play, Pause, Previous, Next and activates each with `:enter` and `:space`, asserting the expected `data-playing` value, `aria-pressed` pair, and frame transition. It also asserts wrap-around in both directions and that no control is `disabled` |
| The muscle list conveys all information without the SVG | Controller test asserts every target name and role appears in the list; system test asserts each SVG carries `aria-hidden="true"` and the list does not |
| System tests cover each visual kind, controls, attribution, SVG safety, and light and dark modes | `test/system/exercise_visual_playback_test.rb` covers image, video, frame sequence, SVG download link, attribution text, and both emulated color schemes, including the dark surface assertion from R11 |

Additional checks not enumerated by the ticket but required by the loaded conventions:
- Class immutability across play and pause (R5).
- The existing transform guard in `test/integration/exercise_visual_rendering_test.rb` keeps passing
  with the new markup (R3).
- The query-count guard calls `get exercise_path(exercise)` (R2).

### Commands
Run `bin/rails tailwindcss:build` first, in this worktree, before any Rails test command.

```
bin/rails tailwindcss:build
bin/rails test test/models/muscle_map_test.rb test/models/exercise_visual_test.rb \
  test/views/exercises/muscle_map_coverage_test.rb \
  test/controllers/exercises_controller_test.rb \
  test/integration/exercise_visual_rendering_test.rb
bin/system-test-browser bin/rails test test/system/exercise_visual_playback_test.rb
bin/system-test-browser bin/rails test test/system/exercises_and_workout_templates_test.rb
PARALLEL_WORKERS=1 bin/system-test-browser bin/rails test:system
bin/rubocop
bin/brakeman --quiet --no-pager --exit-on-warn --exit-on-error
```

The serial `test:system` run is the regression oracle. Do not classify a parallel failure as a
regression without it, or without matched base and head arms.

### Runtime path proof
The production entry point is `GET /exercises/:id`, served by `ExercisesController#show`.
- `@muscle_map` is built in `show` and rendered by `exercises/show.html.erb`.
- The control buttons render inside `exercises/_visual.html.erb`, which `show.html.erb` already calls
  for every persisted visual.
- The existing integration test already drives `get exercise_path(exercise)`; the extended assertions
  ride the same real request.
- The system tests reach the page by the real user path Activities to Library to All exercises to the
  exercise, matching `test/system/exercises_and_workout_templates_test.rb`.

This ticket is not scaffold-only.

## 8. Vault gaps worth capturing

1. **Hearth has no synced Elements preview tree.** Hearth vendors the library locally
   (`app/components/elements`, `config/elements.yml`, `lib/tailwindplus_elements_components`) rather
   than syncing previews into `tmp/`. Two pipeline roles have now spent a round trip on this. A note
   naming Hearth's distribution path, and separating it from the HyperFlex synced-preview path, would
   prevent a repeat. This is the highest-value capture from this ticket.
2. **Data-bearing SVG art is not an icon.** `use-icon-helper-instead-of-raw-svgs-in-elements` reads as
   absolute. A note recording the exception for per-region `data-*` markup would stop this question
   recurring on every diagram, chart, or map ticket.
3. **Reduced motion has no Hearth convention.** The rule that a Stimulus controller reads the media
   query while CSS owns presentation is worth capturing once the implementation lands.
4. **Emulated media in system tests.** `Emulation.setEmulatedMedia` appears only in
   `household_people_and_account_test.rb`. A note naming it as the Hearth technique for both
   `prefers-color-scheme` and `prefers-reduced-motion`, including the `ensure` reset, would make it
   discoverable.
5. **Prove a coverage invariant by rendering, not by a second constant.** Reading emitted
   `data-*` values back out of rendered markup is a stronger invariant than comparing two constants,
   and it keeps geometry in the view layer. Worth generalizing beyond this ticket.
6. **Monochrome source art needs a surface, not a transform.** Hearth solves white vendored art with a
   backdrop rather than an Active Storage transform, reinforcing
   `hearth exercise visuals serve video inline and svg as a download`.
