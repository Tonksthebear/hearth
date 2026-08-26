# Plan — Integrate exercise visuals across workouts (ticket_1787683385_558460)

Run `run_1787777641_557910`. Step `hotwire_plan`. Pipeline `hotwire_rails_app_pipeline`.

## 1. Context loaded

### Pipeline context

- `project_pipelines_current_context` supplied the ticket, run, step, gate, dependencies, and two prior agent answers.
- All four dependency tickets are closed and merged into `origin/main`:
  `ticket_1787683377_217672` (playback and muscle map), `ticket_1787683380_492145` (authoring),
  `ticket_1787683383_337542` (catalog import, update, conflict management),
  `ticket_1787683743_352873` (agent tools and serializers).
- Prior answer `question_1787683474_220074` items 19 to 22 and answer `question_1787683792_427859` item C8
  produced the current ticket description. The description, not the ticket title, is the scope authority.
- Human answer `question_1787777863_778878` settled three readings. See section 3.

### Vault notes read

- `planner-playbook` — role contract and required output.
- `hotwire-app-planner-playbook` — Rails plus Hotwire overlay, layer ownership, test tier choice.
- `hearth exercise visuals serve video inline and svg as a download` — SVG stays binary, never in an `img`;
  `VideoAnalyzer` and `VideoPreviewer` stay disabled; `ExerciseVisualItem#inline_renderable?` is the view gate.
- `hearth exercise visual fixtures stay empty because visuals are assembled in tests` — build visuals through
  `test/test_helpers/exercise_visual_test_helper.rb`, never through visual fixtures.
- `hearth ui pipeline context must route elements conventions` — Elements plus `yass` own markup and styling.
- `hearth backups snapshot the stopped rails storage volume as one restore unit` — backup documentation boundary.
- `hearth merge result vocabulary is shared across merge importer and management ui` — do not add status strings.
- `hearth gate runs require restoring a pipeline wiped gitignore before attribution` — check `.gitignore` before
  attributing any gate failure.

### Repository state read

- Branch `project-pipelines/ticket_1787683385_558460` was two merges behind. It is now fast-forwarded to
  `origin/main` at `67cba7f`.
- `app/models/exercise.rb`, `app/models/exercise_visual.rb`, `app/models/exercise_visual_item.rb`,
  `app/models/exercise/source_merge.rb`, `app/models/muscle_map.rb`.
- `app/models/workout_guide/bundle.rb`, `import.rb`, `import_run.rb`, `app/jobs/workout_guide/import_job.rb`.
- `app/views/exercises/_show.html.erb`, `_visual.html.erb`, `_attribution.html.erb`, `index.html.erb`,
  `app/views/workout_guide_imports/_import.html.erb`.
- `app/views/workout_templates/show.html.erb`, `app/views/training_sessions/show.html.erb`, `_exercise_fields.html.erb`.
- `app/controllers/exercises_controller.rb`, `workout_templates_controller.rb`, `training_sessions_controller.rb`.
- `config/application.rb` lines 19 to 21, `config/storage.yml`, `config/ci.rb`, `README.md` lines 19, 284 to 293, 374 to 379.
- `test/integration/exercise_visual_rendering_test.rb`, `test/controllers/exercises_controller_test.rb`,
  `test/test_helpers/exercise_visual_test_helper.rb`, `test/test_helpers/workout_guide_import_test_helper.rb`.
- `app/views/recipes/index.html.erb` lines 50 to 60 and `app/models/recipe.rb` lines 20 to 22 are the prior art
  for a named Active Storage variant plus an icon placeholder.

## 2. Scope and non-scope

### In scope

1. One shared read-only thumbnail partial for a catalog exercise.
2. Thumbnail rendering on three surfaces: workout template detail, in-progress session recording form, and
   completed session detail.
3. One model-tier rule that selects the thumbnail source and its rendering mode.
4. Preloading so the three surfaces stay query-count bounded.
5. A catalog credits section plus the medical tracking disclaimer on the exercises index.
6. An offline SQLite integration test with the local disk Active Storage service.
7. One focused system test from catalog import through workout use.
8. README backup documentation that names exercise visual files.

### Out of scope

- No new training-session snapshot columns. No change to `TrainingSession.start_from` or
  `TrainingSessionExercise#copy_catalog_snapshot`.
- No muscle-target display changes. Ticket `ticket_1787683377_217672` owns target presentation.
- No agent tool or serializer changes. Ticket `ticket_1787683743_352873` owns
  `HearthMcp::ManagementTools` and `HearthMcp::Serializer`.
- No thumbnails on the exercises index grid.
- No change to exercise detail visual rendering, playback, or the SVG download link there.
- No change to `Exercise::SourceMerge`, `WorkoutGuide::Import`, `WorkoutGuide::ImportRun`, or the import UI.
- No change to `config/ci.rb`, the demo seed, or the demo count assertion.
- No new vendored assets and no new icon files.

## 3. Assumptions and unknowns

### Settled by human answer `question_1787777863_778878`

| Question | Answer |
| --- | --- |
| Thumbnail surfaces | `workout_templates/show`, `training_sessions/edit`, and `training_sessions/show`. Not the exercises index grid. A session row whose `exercise` association is `nil` renders the placeholder without an empty image element and without an exception. |
| SVG in a thumbnail slot | The static placeholder. The SVG download link stays on the exercise detail page only. |
| Muscle targets and agent tools | The revised description is authority. Both stay out of scope. |
| Branch base | `ticket_1787683383_337542` is merged at `67cba7f`. Refresh from `origin/main` and use the merged catalog UI path in the offline test. |
| Variants | Follow the ticket. Variants for `image/png`, `image/jpeg`, and `image/webp` only. Keep the exercise detail page transform-free. Record the narrower exception in the vault. |

### Standing assumptions

- A1. The thumbnail is decorative next to a visible exercise name, so its `img` carries `alt=""` and the
  placeholder carries `aria-hidden="true"`. This matches `app/views/recipes/index.html.erb`.
- A2. `image_tag item.file.variant(:thumb)` produces a representation URL and performs no transform during
  render. This is the same call shape `app/views/recipes/index.html.erb` already uses for `recipe.cover.variant(:card)`.
- A3. The in-progress recording form renders the thumbnail from the persisted `exercise` association. Choosing a
  different catalog exercise in the autocomplete updates the thumbnail after the next structural action or save,
  not on the client. No Stimulus controller is added.
- A4. Catalog credits are built from persisted `Exercise#source_attribution`, not from files under
  `vendor/workout_guide/`. Persisted attribution credits exactly what the household holds and avoids per-request
  file input and output.
- A5. `docs/plans/` is the plan location, matching `docs/plans/exercise-visual-playback-and-muscle-map.md`.

### Unknowns for the Implementer

- U1. The exact bounded query counts for the three surfaces. Measure them, then assert the measured value, in the
  style of `test/controllers/exercises_controller_test.rb` line 316.
- U2. The exact thumbnail pixel box. Start at `resize_to_limit: [ 160, 160 ]`. `resize_to_limit` preserves the
  aspect ratio, which matters because Workout Guide frames are transparent 512 by 512 art that cropping would damage.

## 4. Affected surfaces and files

### Models

- `app/models/exercise_visual_item.rb`
  - Add `THUMBNAIL_VARIANT_CONTENT_TYPES = %w[image/png image/jpeg image/webp].freeze`.
  - Declare the named variant on the existing attachment:
    `has_one_attached :file do |attachable| attachable.variant :thumb, resize_to_limit: [ 160, 160 ] end`.
  - Add one predicate `thumbnail_rendering` returning `:variant`, `:original`, or `:placeholder`.
    `:variant` for the three variant content types. `:original` for `image/gif`. `:placeholder` for every other
    case, which covers `image/svg+xml`, both video content types, and a missing attachment.
- `app/models/exercise_visual.rb`
  - Add `thumbnail_item` returning `sorted_items.first`.
- `app/models/exercise.rb`
  - Add `thumbnail_visual` returning the first visual by position.
  - Add `thumbnail_item` and `thumbnail_rendering`, which returns `:placeholder` when no item exists.
  - Add `thumbnail_dark_surface?` returning `thumbnail_visual&.unmodified_source_art?` so the thumbnail reuses
    the same `bg-gray-950` rule the exercise detail page applies in `app/views/exercises/_visual.html.erb` line 14.
  - Add `catalog_credits` as a class method on the source-linked scope. It returns the distinct present
    attribution hashes, using the existing `Exercise::SourceMerge::ATTRIBUTION_FIELDS` order.

`thumbnail_rendering` is one predicate behind the view gate. It keeps content-type branching out of ERB and out
of every controller.

### Views

- `app/views/exercises/_thumbnail.html.erb` — new. Local `exercise:`, which may be `nil`. Three branches:
  a variant `image_tag`, an original `image_tag` through `rails_storage_proxy_path`, or an
  `icon "bolt", variant: :solid` placeholder block. It applies `bg-gray-950` when `exercise.thumbnail_dark_surface?`.
  It never emits an `img` without a source.
- `app/views/workout_templates/show.html.erb` — render the partial in each prescription row, line 22 to 27.
- `app/views/training_sessions/show.html.erb` — render the partial in each exercise block, line 25 to 41,
  passing `exercise.exercise`, which may be `nil`.
- `app/views/training_sessions/_exercise_fields.html.erb` — render the partial beside the "Exercise N" heading,
  line 12 to 15, passing `form.object.exercise`, which may be `nil`.
- `app/views/exercises/index.html.erb` — render a new credits partial below the catalog import panel.
- `app/views/workout_guide_imports/_credits.html.erb` — new. Renders `@catalog_credits` and the disclaimer.
  The disclaimer reuses the exact sentence already on `app/views/workout_templates/show.html.erb` line 37:
  "Provenance is attribution, not clinical endorsement. Hearth is a tracking tool and does not provide medical advice."
  The section renders nothing when the household has no source-linked exercise.

Markup follows the existing Hearth card, `yass`, and `icon` idiom in these files. No hand-rolled control is added.

### Controllers

- `app/controllers/workout_templates_controller.rb` `show` — extend the existing `includes` to
  `exercise_prescriptions: { exercise: { exercise_visuals: { exercise_visual_items: { file_attachment: :blob } } } }`.
- `app/controllers/training_sessions_controller.rb` `set_training_session` — preload
  `training_session_blocks: { training_session_exercises: { exercise: { exercise_visuals: { exercise_visual_items: { file_attachment: :blob } } } } }`
  for `show` and `edit`.
- `app/controllers/exercises_controller.rb` `index` — assign `@catalog_credits`.

### Documentation

- `README.md` line 19 — name exercise visual files beside recipe cover files in the storage sentence.
- `README.md` line 291 — extend "Active Storage originals and generated variants, including recipe cover images"
  to name exercise visual originals and generated thumbnails.
- `README.md` line 377 — add an exercise visual to the post-upgrade inspection list.

## 5. Risks

- R1. Convention conflict. The vault note `hearth exercise visuals serve video inline and svg as a download`
  states that Hearth excludes every visual type from Active Storage transforms. This ticket requires variants
  for three raster content types. Resolution: the human confirmed the ticket is authority, the exercise detail
  page stays transform-free, and the narrower thumbnail exception is captured in the vault.
- R2. `test/integration/exercise_visual_rendering_test.rb` prepends `ExerciseVisualTransformGuard` to
  `ActiveStorage::Attachment` and `ActiveStorage::Blob` for the whole test process. It raises only while
  `Thread.current[:exercise_visual_forbid_transforms]` is true, which the test sets around the exercise detail
  request only. Thumbnail variants on other surfaces do not trip it. The Implementer must not widen that flag.
- R3. `ActiveStorage::InvariableError`. Calling `variant` on an SVG or a video blob raises. The
  `thumbnail_rendering` predicate is the only guard. Every branch must be covered by a test.
- R4. Query count regression on three surfaces. Without the added preloads each prescription and each session
  exercise triggers separate visual, item, attachment, and blob queries. Bounded query-count tests are required.
- R5. `Exercise.catalog_credits` reads `source_snapshot` for every source-linked exercise. The vendored bundle
  carries 302 records, and each snapshot also holds visual checksums. This is one query with a real payload on
  the exercises index. Mitigation: select only what is needed and assert a bounded query count. A denormalized
  credits column is a larger change than this ticket justifies, so it is not planned.
- R6. Nullified associations. `Exercise has_many :training_session_exercises, dependent: :nullify`. Both session
  surfaces must tolerate `exercise` being `nil`. This is the acceptance criterion "Deleted source records do not
  break historical sessions".
- R7. System test cost. The vendored bundle holds 302 records and 906 frames. The focused system test must use
  `with_fixture_workout_guide_import`, which points `WorkoutGuide::Import` at the three-record fixture bundle at
  `test/fixtures/files/workout_guide`.
- R8. Worktree damage. Per the vault gotcha, inspect the `.gitignore` diff before attributing any gate failure.
  On this worktree the file arrived with five extra local lines that `origin/main` now carries as committed
  content, so the working tree is clean after the fast-forward.

## 6. Acceptance checks and tests

### New and changed tests

1. `test/models/exercise_visual_item_test.rb` — `thumbnail_rendering` returns `:variant` for `image/png`,
   `image/jpeg`, and `image/webp`; `:original` for `image/gif`; `:placeholder` for `image/svg+xml`,
   `video/mp4`, `video/webm`, and an unattached item.
2. `test/models/exercise_test.rb` — `thumbnail_item` returns the first item of the first visual by position, and
   proves the rule against an exercise whose visuals and items were created out of position order.
   `thumbnail_rendering` returns `:placeholder` for an exercise with no visual.
   `thumbnail_dark_surface?` is true only for unmodified Workout Guide source art.
   `catalog_credits` returns distinct present attribution rows and an empty result for a household with no
   source-linked exercise.
3. `test/controllers/workout_templates_controller_test.rb` — the show page renders one thumbnail per prescription;
   a variant thumbnail uses a representation URL; a GIF thumbnail uses the proxy URL for the original; an SVG-first,
   video-first, and visual-free exercise each render the placeholder; the response contains no `img` without a
   `src`; the query count stays at the measured bound.
4. `test/controllers/training_sessions_controller_test.rb` — the same thumbnail assertions on `show` and `edit`;
   a `training_session_exercise` whose `exercise_id` is `nil` renders the placeholder and returns success;
   the query count stays at the measured bound on both actions.
5. `test/controllers/exercises_controller_test.rb` — the index renders the credits section and the disclaimer
   sentence when the household holds source-linked exercises, and renders neither when it does not.
6. `test/integration/offline_catalog_to_workout_test.rb` — new. It asserts the connection adapter is SQLite and
   `ActiveStorage::Blob.service` is a `Disk` service. It installs an outbound-network guard that raises on
   `TCPSocket.open` and `Net::HTTP#request`, in the same prepend style the repository already uses in
   `test/integration/exercise_visual_rendering_test.rb`. Inside the guard it posts to `workout_guide_import_path`,
   performs the enqueued `WorkoutGuide::ImportJob`, then requests the workout template and training session pages
   and asserts a rendered thumbnail. It uses `with_fixture_workout_guide_import`.
7. `test/system/exercise_visuals_in_workouts_test.rb` — new, one focused test. It signs in, imports the fixture
   catalog through the real index button, opens an imported exercise, builds a workout template that prescribes
   it, starts a training session, and asserts a visible thumbnail image on the template page and on the
   recording form.

### Existing tests that must pass unchanged

- `test/models/training_session_test.rb` and `test/models/training_session_exercise_test.rb`. No snapshot
  behavior changes and no snapshot column is added.
- `test/integration/exercise_visual_rendering_test.rb`. The exercise detail page still calls no transform, and
  its `assert_no_match` on representation and variant URLs still holds.
- `test/system/exercise_visual_playback_test.rb` and `test/system/exercises_and_workout_templates_test.rb`.
- `test/controllers/exercises_controller_test.rb` line 316, the bounded exercise show query count. The added
  `@catalog_credits` assignment is on `index`, not `show`, so this bound is unchanged.

### Runtime path evidence

Every change reaches a production entry point.

| Change | Production entry point |
| --- | --- |
| `thumbnail_rendering` and the thumbnail partial | `GET /workout_templates/:id`, `GET /training_sessions/:id`, `GET /training_sessions/:id/edit` |
| Preloads | The same three actions |
| `catalog_credits` and the disclaimer | `GET /exercises` |
| Offline import path | `POST /workout_guide_import` plus `WorkoutGuide::ImportJob` |
| README backup documentation | Operator procedure, verified by review of the changed lines |

### Commands

- `bin/rubocop`
- `bin/rails test`
- `bin/system-test-browser bin/rails test:system`
- `bin/brakeman --quiet --no-pager --exit-on-warn --exit-on-error`

Run `bin/rails test` serially for the regression oracle when a system test result is contested, per
`hearth parallel system tests flake so a serial run is the regression oracle`. `config/ci.rb` is not changed,
so a full `bin/ci` run is not obliged by
`a hearth change to config ci rb obliges a bin ci run`.

## 7. Vault gaps worth capturing

1. Narrow the transform rule. `hearth exercise visuals serve video inline and svg as a download` currently reads
   as a blanket exclusion of Active Storage transforms for every visual type. The true rule after this ticket is:
   exercise detail visuals call no transform, and workout thumbnails use a named variant for `image/png`,
   `image/jpeg`, and `image/webp` only. GIF, SVG, and video never reach a transform anywhere.
2. Capture the thumbnail selection rule as a Hearth convention: the first item of the first visual by position,
   with a `bolt` icon placeholder for SVG, video, and visual-free exercises, and the same dark surface the
   exercise detail page applies to unmodified Workout Guide art.
3. Capture that Hearth workout surfaces that render catalog thumbnails must tolerate a nullified
   `TrainingSessionExercise#exercise`, because `Exercise` nullifies that association on destroy.
4. Capture that Hearth offline evidence uses a prepended outbound-network guard plus explicit SQLite adapter and
   Disk service assertions, rather than a claim that no network call occurred.
5. Note for the pipeline: this run began on a stale worktree that missed two merged dependency branches, and one
   dependency was reported closed while its merge had not yet been fetched. Roles should fetch `origin` and
   fast-forward before treating a closed dependency as absent.
