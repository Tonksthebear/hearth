# Plan — Integrate exercise visuals across workouts (ticket_1787683385_558460)

Run `run_1787777641_557910`. Step `hotwire_plan`. Pipeline `hotwire_rails_app_pipeline`.

Revision 3. Revision 2 answered the eight findings of review `review_1787779241_654325` and human answer
`question_1787779055_423059`; section 9 maps those. Revision 3 answers the three findings of review
`review_1787779890_852082`; section 10 maps those.

## 1. Context loaded

### Pipeline context

- `project_pipelines_current_context` supplied the ticket, run, step, gate, dependencies, reviews, findings, and
  question answers.
- All four dependency tickets are closed and merged into `origin/main`:
  `ticket_1787683377_217672` (playback and muscle map), `ticket_1787683380_492145` (authoring),
  `ticket_1787683383_337542` (catalog import, update, conflict management),
  `ticket_1787683743_352873` (agent tools and serializers).
- Prior answers `question_1787683474_220074` and `question_1787683792_427859` produced the current ticket
  description. The description, not the ticket title, is the scope authority.
- Human answer `question_1787777863_778878` settled the thumbnail surfaces, the SVG slot, the muscle-target
  boundary, the branch base, and the variant exception.
- Human answer `question_1787779055_423059` settled the disclaimer rule. See section 3.

### Vault notes read

Role and stack entrypoints.

- `planner-playbook` — role contract and required output.
- `hotwire-app-planner-playbook` — Rails plus Hotwire overlay, layer ownership, test tier choice.
- `rails-conventions` — Testing, Views and Interactivity, Data Flow, Authorization, and Gotchas sections.
- `hotwire-patterns` — server-rendered frontend conventions.
- `hearth-overview` — the Workout Guide and Exercise Visuals, User Interface, and Verification sections.

Architecture.

- `fat models over service objects` — domain behavior on models and POROs.
- `controllers prepare data views render only` — prepared view data before ERB renders it.
- `styles and html live in html not javascript` — presentation in HTML and Tailwind.

Hearth Elements packet.

- `hearth ui pipeline context must route elements conventions` — every role loads the Elements packet.
- `hearth uses tailwindplus elements as its default ui system` — Elements is the default presentation system.
- `hearth vendors elements locally and has no preview tree` — Hearth has no
  `tmp/tailwindplus_elements_previews`. Its authoritative sources are `app/components/elements`,
  `config/elements.yml`, `lib/tailwindplus_elements_components`, the vendored Elements JavaScript, and existing
  Hearth views. Controls reuse the existing `yass(btn: ...)` axis. This plan requires no preview tree.
- `data bearing svg maps are not icon helper assets` — the body map keeps geometry in an ERB partial. The
  thumbnail placeholder is decorative, carries no data attributes, and therefore correctly uses the `icon` helper.

Exercise visuals and catalog.

- `hearth exercise visuals serve video inline and svg as a download`.
- `forbidden active storage transforms need raising guards on attachment and blob`.
- `hearth exercise visual fixtures stay empty because visuals are assembled in tests`.
- `hearth catalog source merge keeps its three way base on the record`.
- `hearth merge result vocabulary is shared across merge importer and management ui`.
- `hearth provenance status is content provenance never source identity`.
- `hearth allows one household per installation so per-household isolation is a model tier claim`.
- `hearth catalog imports require one explicit household id`.

Verification.

- `query count guards must call the production entry point`.
- `bounded query regressions need constant sql growth and rendered row caps`.
- `scope tests need both inclusion and exclusion fixtures to catch silent-filter bugs`.
- `hearth controller and integration tests need a tailwind build not only system tests`.
- `hearth parallel system tests flake so a serial run is the regression oracle`.
- `brakeman exit code 5 signals outdated gem version not scan failure`.
- `a minitest failure line is the assertion location not the test definition`.
- `hearth gate runs require restoring a pipeline wiped gitignore before attribution`.
- `a hearth change to config ci rb obliges a bin ci run`.
- `rails integration tests enter through the user facing get and complete the full flow`.

### Repository state read

- The branch was two merges behind. It is fast-forwarded to `origin/main` at `67cba7f`. The plan commit is on top.
- Models: `exercise.rb`, `exercise_visual.rb`, `exercise_visual_item.rb`, `exercise/source_merge.rb`,
  `muscle_map.rb`, `workout_guide/bundle.rb`, `import.rb`, `import_run.rb`, `app/jobs/workout_guide/import_job.rb`.
- Views: `exercises/_show.html.erb`, `_visual.html.erb`, `_attribution.html.erb`, `index.html.erb`,
  `workout_guide_imports/_import.html.erb`, `workout_templates/show.html.erb`,
  `training_sessions/show.html.erb`, `training_sessions/_exercise_fields.html.erb`.
- Controllers: `exercises_controller.rb`, `workout_templates_controller.rb`, `training_sessions_controller.rb`.
- Config and docs: `config/application.rb` lines 19 to 21, `config/storage.yml`, `config/ci.rb`,
  `README.md` lines 19, 284 to 293, 374 to 379.
- Tests and helpers: `test/integration/exercise_visual_rendering_test.rb`,
  `test/controllers/exercises_controller_test.rb`, `test/test_helpers/exercise_visual_test_helper.rb`,
  `test/test_helpers/workout_guide_import_test_helper.rb`.

### Local implementation source

`app/views/recipes/index.html.erb` lines 50 to 60, with `app/models/recipe.rb` lines 20 to 22, is the
Elements-compatible local implementation source for this work. It already pairs a named Active Storage variant
with an `icon` placeholder inside a Hearth card. The thumbnail partial follows that exact shape. No preview tree
is needed, per `hearth vendors elements locally and has no preview tree`.

### Runtime facts measured on this worktree

Measured with `RAILS_ENV=test bin/rails runner` at the plan commit.

- libvips 8.18.4 is present and `active_storage.variant_processor` is `:vips`.
- A real Workout Guide frame, `vendor/workout_guide/assets/bench-press/frame-1.png`, variants through
  `resize_to_limit: [ 160, 160 ]` and produces an 8685-byte `image/png`. Variant generation is therefore proven
  available before implementation begins.
- `ActiveStorage::Blob.new(content_type: "image/svg+xml").variable?` is `false`.
- `ActiveStorage::Blob.new(content_type: "image/gif").variable?` is `true`.

The GIF fact matters. Rails would happily variant a GIF and flatten its animation. Excluding GIF from the variant
set is a deliberate Hearth decision, not something Rails enforces. This is why `thumbnail_rendering` owns the
decision and the code never branches on `blob.variable?`.

## 2. Scope and non-scope

### In scope

1. One shared read-only thumbnail partial for a catalog exercise.
2. Thumbnail rendering on three surfaces: workout template detail, in-progress session recording form, and
   completed session detail.
3. One model-tier rule that selects the thumbnail source and its rendering mode.
4. Preloading so the three surfaces hold constant query growth.
5. The medical tracking disclaimer on the exercises index, always rendered, plus Workout Guide catalog credits
   rendered only when the household holds at least one source-linked Workout Guide exercise.
6. An offline SQLite integration test with the local disk Active Storage service.
7. One focused system test from catalog import through workout use.
8. README backup documentation that names exercise visual files.
9. Extraction of the existing Active Storage transform guard into a shared test helper, so the new negative tests
   and the existing one use a single guard.

Item 9 is cleanup made necessary by this change. The guard must now protect four request paths instead of one.

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
- No new vendored assets and no new icon files. Heroicons `bolt` is already vendored in
  `app/assets/svg/icons/heroicons/solid`.

## 3. Assumptions and unknowns

### Settled by human answer `question_1787777863_778878`

| Question | Answer |
| --- | --- |
| Thumbnail surfaces | `workout_templates/show`, `training_sessions/edit`, and `training_sessions/show`. Not the exercises index grid. A session row whose `exercise` association is `nil` renders the placeholder without an empty image element and without an exception. |
| SVG in a thumbnail slot | The static placeholder. The SVG download link stays on the exercise detail page only. |
| Muscle targets and agent tools | The revised description is authority. Both stay out of scope. |
| Branch base | `ticket_1787683383_337542` is merged at `67cba7f`. Use the merged catalog UI path in the offline test. |
| Variants | Variants for `image/png`, `image/jpeg`, and `image/webp` only. The exercise detail page stays transform-free. Record the narrower exception in the vault. |

### Settled by human answer `question_1787779055_423059`

The medical tracking disclaimer always renders on the exercises index. It applies to Hearth exercise tracking and
planning, including household-created exercises. It stays concise and non-clinical. Workout Guide catalog credits
render only when the household holds at least one source-linked Workout Guide exercise. Tests must cover an empty
or personal-only catalog and a source-linked catalog.

### Standing assumptions

- A1. The thumbnail is decorative next to a visible exercise name, so its `img` carries `alt=""` and the
  placeholder carries `aria-hidden="true"`. This matches `app/views/recipes/index.html.erb`.
- A2. `image_tag item.file.variant(:thumb)` emits a representation URL and performs no transform during render.
  This is the same call shape `app/views/recipes/index.html.erb` already uses for `recipe.cover.variant(:card)`.
  Test 6 in section 6 proves the absence of `preview` and `representation` on that path rather than assuming it.
- A3. The in-progress recording form renders the thumbnail from the persisted `exercise` association. Choosing a
  different catalog exercise in the autocomplete updates the thumbnail after the next structural action or save,
  not on the client. No Stimulus controller is added.
- A4. Catalog credits are built from persisted `Exercise#source_attribution`, not from files under
  `vendor/workout_guide/`. Persisted attribution credits exactly what the household holds and avoids per-request
  file input and output.
- A5. `docs/plans/` is the plan location, matching `docs/plans/exercise-visual-playback-and-muscle-map.md`.

### Unknowns for the Implementer

- U1. The exact thumbnail pixel box. Start at `resize_to_limit: [ 160, 160 ]`, the value measured in section 1.
  `resize_to_limit` preserves the aspect ratio, which matters because Workout Guide frames are transparent 512 by
  512 art that cropping would damage.
- U2. Whether the credits list needs a rendered-row cap. The current bundle yields a handful of distinct
  attribution rows because `creator` and `license` are uniform across Workout Guide. If a future source makes the
  deduplicated list long, apply the rendered-row ceiling rule from
  `bounded query regressions need constant sql growth and rendered row caps`. Section 6 test 9 asserts the
  deduplicated row count so the growth behavior is observable rather than assumed.

No query-count value is left unknown. Section 6 replaces absolute counts with a growth invariant.

## 4. Affected surfaces and files

### Models

- `app/models/exercise_visual_item.rb`
  - Add `THUMBNAIL_VARIANT_CONTENT_TYPES = %w[image/png image/jpeg image/webp].freeze`.
  - Declare the named variant on the existing attachment:
    `has_one_attached :file do |attachable| attachable.variant :thumb, resize_to_limit: [ 160, 160 ] end`.
  - Add one predicate `thumbnail_rendering` returning `:variant`, `:original`, or `:placeholder`.
    `:variant` for the three variant content types. `:original` for `image/gif`. `:placeholder` for every other
    case, which covers `image/svg+xml`, both video content types, and a missing attachment.
    The predicate never consults `blob.variable?`, because GIF is variable and must still render as an original.
- `app/models/exercise_visual.rb`
  - Add `thumbnail_item` returning `sorted_items.first`.
- `app/models/exercise.rb`
  - Add `thumbnail_visual` returning the first visual by position.
  - Add `thumbnail_item` and `thumbnail_rendering`, which returns `:placeholder` when no item exists.
  - Add `thumbnail_dark_surface?` returning `thumbnail_visual&.unmodified_source_art?` so the thumbnail reuses
    the same `bg-gray-950` rule the exercise detail page applies in `app/views/exercises/_visual.html.erb` line 14.
  - Add `catalog_credits` as a class method reachable through a relation, so the caller supplies the household
    boundary. See the scoping rule below.

`thumbnail_rendering` is one predicate behind the view gate. It keeps content-type branching out of ERB and out
of every controller.

### Household and namespace scoping rule for credits

`catalog_credits` is a relation-scoped class method. The only production caller is
`Current.household.exercises.from_source_namespace(WorkoutGuide::Import::SOURCE_NAMESPACE)`, in
`ExercisesController#index`. The method never reads `Exercise.all` and never reaches `Current` itself, so the
household boundary stays at the controller seam that `app/controllers/exercises_controller.rb` line 6 already
uses for `@exercises`.

Two boundaries apply, not one.

- Household. Supplied by `Current.household.exercises`.
- Source namespace. Supplied by the existing `from_source_namespace` scope in `app/models/exercise.rb`, which
  matches `source_key LIKE 'workout_guide:%'` with a `LIKE` escape.

`from_source` alone is wrong here. It matches every source namespace, so a future non-Workout-Guide catalog
would render its attribution under a Workout Guide credits heading. The human answer scopes credits to
source-linked Workout Guide exercises specifically, so the namespace scope is required. The same namespace scope
governs the inclusion, exclusion, and conditional-render tests in section 6.

It returns the distinct attribution hashes for the household's Workout Guide exercises, using the existing
`Exercise::SourceMerge::ATTRIBUTION_FIELDS` order and dropping fields whose value is blank.

Per `hearth allows one household per installation so per-household isolation is a model tier claim`,
`Household` restricts `installation_key` to 1, so there is no reachable production path for a two-household
request test. The exclusion proof is therefore a model-tier claim built with the existing
`insert_foreign_exercise` helper in `test/test_helpers/workout_guide_import_test_helper.rb`. Section 6 test 10
states this tier limit explicitly, and no report may claim a two-household runtime proof.

### Credit presentation contract

The seven persisted fields in `Exercise::SourceMerge::ATTRIBUTION_FIELDS` render as follows.

| Field | Rendering |
| --- | --- |
| `creator` | Text. Rendered as a link when `creator_url` is present. |
| `creator_url` | Never rendered on its own. It supplies the `creator` link target. |
| `source_name` | Text. Rendered as a link when `source_url` is present. |
| `source_url` | Never rendered on its own. It supplies the `source_name` link target. |
| `license` | Text. Rendered as a link when `license_url` is present. |
| `license_url` | Never rendered on its own. It supplies the `license` link target. |
| `change_note` | Text. Never a link. |

A blank value renders neither its label nor an empty element. A URL whose paired text field is blank renders
nothing, because a bare URL is not a credit. Identical attribution rows collapse to one rendered row.

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
- `app/views/exercises/index.html.erb` — render the disclaimer partial unconditionally, and the credits partial
  below the catalog import panel.
- `app/views/exercises/_tracking_disclaimer.html.erb` — new. One concise, non-clinical sentence, always rendered.
  It reuses the exact sentence already on `app/views/workout_templates/show.html.erb` line 37:
  "Provenance is attribution, not clinical endorsement. Hearth is a tracking tool and does not provide medical advice."
- `app/views/workout_guide_imports/_credits.html.erb` — new. Renders `@catalog_credits` under the contract above.
  It renders nothing when `@catalog_credits` is empty.

Markup follows the existing Hearth card, `yass`, and `icon` idiom in these files. No hand-rolled control is added,
and no Elements preview tree is required.

### Controllers

- `app/controllers/workout_templates_controller.rb` `show` — extend the existing `includes` to
  `exercise_prescriptions: { exercise: { exercise_visuals: { exercise_visual_items: { file_attachment: :blob } } } }`.
- `app/controllers/training_sessions_controller.rb` `set_training_session` — preload
  `training_session_blocks: { training_session_exercises: { exercise: { exercise_visuals: { exercise_visual_items: { file_attachment: :blob } } } } }`
  for `show` and `edit`.
- `app/controllers/exercises_controller.rb` `index` — assign
  `@catalog_credits = Current.household.exercises.from_source_namespace(WorkoutGuide::Import::SOURCE_NAMESPACE).catalog_credits`.

### Test helpers

- `test/test_helpers/active_storage_transform_guard.rb` — new. It moves the guard currently defined inline in
  `test/integration/exercise_visual_rendering_test.rb` lines 4 to 17 into one shared helper.
  Per `forbidden active storage transforms need raising guards on attachment and blob`, it prepends to both
  `ActiveStorage::Attachment` and `ActiveStorage::Blob` and raises for all six class-and-method combinations of
  `variant`, `preview`, and `representation` when a thread-local flag is set. The thread-local flag keeps the
  guard inactive for parallel workers.
  It exposes `with_forbidden_active_storage_transforms(*method_names) { ... }` so a caller can forbid all three
  methods on a page that renders no variant, or forbid only `preview` and `representation` on a page that
  legitimately renders one.
- `test/integration/exercise_visual_rendering_test.rb` — use the shared helper. The existing assertions do not change.

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
- R2. The transform guard must not be widened. The exercise detail page must keep forbidding all three methods.
  The workout template and session pages forbid all three only for GIF, SVG, video, and visual-free thumbnails,
  and forbid `preview` and `representation` for raster thumbnails. Extracting the guard makes both settings
  explicit at each call site instead of implied by one test file.
- R3. `ActiveStorage::InvariableError`. Calling `variant` on an SVG or a video blob raises. Measured:
  `image/svg+xml` reports `variable?` as `false`. The `thumbnail_rendering` predicate is the only guard, and
  every branch is covered by a test.
- R4. GIF is variable in Rails. Measured: `image/gif` reports `variable?` as `true`. A future edit that replaces
  the explicit content-type list with `blob.variable?` would silently flatten animated GIFs. Test 1 pins the GIF
  branch to `:original` so that edit fails.
- R5. Query growth on three surfaces. Without the added preloads each prescription and each session exercise
  triggers separate visual, item, attachment, and blob queries. Section 6 proves constant growth rather than a
  measured absolute count.
- R6. Nullified associations. `Exercise has_many :training_session_exercises, dependent: :nullify`. Both session
  surfaces must tolerate `exercise` being `nil`. This is the acceptance criterion "Deleted source records do not
  break historical sessions".
- R7. System test cost. The vendored bundle holds 302 records and 906 frames. The focused system test must use
  `with_fixture_workout_guide_import`, which points `WorkoutGuide::Import` at the three-record fixture bundle at
  `test/fixtures/files/workout_guide`.
- R8. Credits payload. `catalog_credits` reads `source_snapshot` for every Workout Guide exercise, and those
  snapshots also hold visual checksums. This is one query with a real payload on the exercises index. A
  denormalized credits column is a larger change than this ticket justifies. Section 6 test 9 asserts constant
  query growth for the index so a later regression is observable.
- R9. Worktree damage. Per `hearth gate runs require restoring a pipeline wiped gitignore before attribution`,
  inspect the `.gitignore` diff before attributing any gate failure. On this worktree the file is clean after the
  fast-forward, because `origin/main` now carries the five previously untracked lines as committed content.
- R10. Missing Tailwind build. Per `hearth controller and integration tests need a tailwind build not only
  system tests`, a fresh worktree has an empty `app/assets/builds`, and layout-rendering controller and
  integration tests then fail with "The asset 'tailwind.css' was not found in the load path." Run
  `bin/rails tailwindcss:build` before every Rails test command. This was run on this worktree at the plan commit.

## 6. Acceptance checks and tests

Run `bin/rails tailwindcss:build` before every Rails test command.

### New and changed tests

1. `test/models/exercise_visual_item_test.rb` — `thumbnail_rendering` returns `:variant` for `image/png`,
   `image/jpeg`, and `image/webp`; `:original` for `image/gif`; `:placeholder` for `image/svg+xml`,
   `video/mp4`, `video/webm`, and an unattached item. The GIF case is asserted explicitly so a later switch to
   `blob.variable?` fails.
2. `test/models/exercise_test.rb` — `thumbnail_item` returns the first item of the first visual by position, and
   proves the rule against an exercise whose visuals and items were created out of position order.
   `thumbnail_rendering` returns `:placeholder` for an exercise with no visual.
   `thumbnail_dark_surface?` is true only for unmodified Workout Guide source art.
3. `test/controllers/workout_templates_controller_test.rb` — `GET /workout_templates/:id` renders one thumbnail
   node per prescription; a raster thumbnail carries a representation URL; a GIF thumbnail carries the proxy URL
   for the original; SVG-first, video-first, and visual-free exercises each render the placeholder; the response
   contains no `img` without a `src`.

   **Dark surface, rendered proof.** The same action asserts `bg-gray-950` is present on the thumbnail wrapper
   for an exercise whose first visual is unmodified Workout Guide source art, and absent for a personal
   exercise and for an exercise whose source art the household has modified. The model predicate test in item 2
   is not sufficient on its own: a missing class in `app/views/exercises/_thumbnail.html.erb` would leave the
   model test green while the user path renders white art on a white card. This assertion runs on a real
   controller action, so it fails when the partial drops the class.
4. `test/controllers/training_sessions_controller_test.rb` — the same thumbnail assertions on
   `GET /training_sessions/:id` and `GET /training_sessions/:id/edit`; a `training_session_exercise` whose
   `exercise_id` is `nil` renders the placeholder and returns success.
5. **Forbidden transform proof, all three surfaces.** Using
   `with_forbidden_active_storage_transforms(:variant, :preview, :representation)`, drive
   `GET /workout_templates/:id`, `GET /training_sessions/:id`, and `GET /training_sessions/:id/edit` against a
   household whose thumbnails are `image/gif`, `image/svg+xml`, `video/mp4`, `video/webm`, and visual-free. No
   guard may raise. This proves absence at the method boundary, which a URL assertion cannot do.
6. **Forbidden transform proof, raster surfaces.** Using
   `with_forbidden_active_storage_transforms(:preview, :representation)`, drive the same three actions against
   `image/png`, `image/jpeg`, and `image/webp` thumbnails. `variant` is permitted; `preview` and `representation`
   must never be called. This closes the ticket rule that no video preview is ever generated.
7. **Usable generated thumbnail.** With the local Disk service, follow the rendered representation URL for a
   PNG, JPEG, and WebP thumbnail and require a successful response with an image content type and a non-empty
   body. The system test in item 12 adds a browser check that the thumbnail `naturalWidth` is greater than zero.
   Section 1 already measured that a real Workout Guide frame variants to an 8685-byte `image/png`, so this test
   pins behavior that is known to be reachable.
8. **Constant query growth, per action.** Per `query count guards must call the production entry point` and
   `bounded query regressions need constant sql growth and rendered row caps`, call each production entry point
   twice with an uncached connection: once with one rendered exercise and once with several. Assert the SQL count
   is equal across both arms for all four actions: `GET /workout_templates/:id`, `GET /training_sessions/:id`,
   `GET /training_sessions/:id/edit`, and `GET /exercises`. No absolute count is asserted, so the contract
   survives unrelated query changes.

   The paired rendered-row check differs by surface, because the exercises index grid deliberately has no
   thumbnails.

   - `workout_templates#show`, `training_sessions#show`, and `training_sessions#edit`: assert the rendered
     thumbnail node count equals the rendered exercise count, so a constant query count cannot hide a missing
     thumbnail.
   - `exercises#index`: assert exactly one rendered disclaimer and the expected credit-row count. Asserting
     thumbnail nodes here would contradict the non-scope rule in section 2.
9. `test/controllers/exercises_controller_test.rb`, disclaimer and credits.
   - The disclaimer sentence renders exactly once for an empty catalog, for a personal-only catalog, and for a
     catalog holding Workout Guide exercises. Three cases, per the human answer.
   - Credits render only in the Workout Guide case, and render for neither of the first two.
   - Namespace boundary: an exercise carrying a `source_key` in some other namespace does not render credits and
     does not contribute a credit row, because the index scopes through
     `from_source_namespace(WorkoutGuide::Import::SOURCE_NAMESPACE)`.
   - Credits presentation: `creator` links to `creator_url`; `source_name` links to `source_url`; `license` links
     to `license_url`; `change_note` renders as text with no link; a blank optional field renders neither a label
     nor an empty element; a URL whose paired text field is blank renders nothing; two exercises carrying
     identical attribution collapse to one rendered row. The test asserts the deduplicated row count.
10. `test/models/exercise_test.rb`, household and namespace exclusion. All three assertions run against
    `households(:home).exercises.from_source_namespace(WorkoutGuide::Import::SOURCE_NAMESPACE).catalog_credits`.
    - Exclusion by household: build a foreign source-linked exercise with the existing `insert_foreign_exercise`
      helper and assert its attribution is absent.
    - Exclusion by namespace: build a household exercise whose `source_key` uses a different namespace and assert
      its attribution is absent.
    - Inclusion: assert a household-owned Workout Guide row is present, per
      `scope tests need both inclusion and exclusion fixtures to catch silent-filter bugs`, so a silent empty
      filter cannot pass.

    The test and any report must record the tier limit from
    `hearth allows one household per installation so per-household isolation is a model tier claim`: the
    household half is a model-tier claim, not a two-household runtime proof. The namespace half has no such
    limit and is also proven at the request tier by test 9.
11. `test/integration/offline_catalog_to_workout_test.rb` — new. It asserts the connection adapter is SQLite and
    `ActiveStorage::Blob.service` is a `Disk` service. It installs an outbound-network guard that raises on
    `TCPSocket.open` and `Net::HTTP#request`, in the same prepend style the shared transform guard uses. Per
    `rails integration tests enter through the user facing get and complete the full flow`, it enters at
    `GET /exercises`, posts to `workout_guide_import_path`, performs the enqueued `WorkoutGuide::ImportJob`, then
    requests the workout template and training session pages and asserts a rendered thumbnail. It uses
    `with_fixture_workout_guide_import`.
12. `test/system/exercise_visuals_in_workouts_test.rb` — new, one focused test. It signs in, imports the fixture
    catalog through the real index button, opens an imported exercise, builds a workout template that prescribes
    it, starts a training session, and asserts a visible thumbnail on the template page and on the recording
    form, including `naturalWidth` greater than zero for the generated raster thumbnail.

### Existing tests that must pass unchanged

- `test/models/training_session_test.rb` and `test/models/training_session_exercise_test.rb`. No snapshot
  behavior changes and no snapshot column is added.
- `test/integration/exercise_visual_rendering_test.rb`. Its guard moves to the shared helper and its assertions
  do not change. The exercise detail page still calls no transform.
- `test/system/exercise_visual_playback_test.rb` and `test/system/exercises_and_workout_templates_test.rb`.
- `test/controllers/exercises_controller_test.rb` line 316, the bounded exercise show query count. The added
  `@catalog_credits` assignment is on `index`, not `show`, so this bound is unchanged.

### Baseline failures carried into implementation

Measured on this worktree at the plan commit, after `bin/rails tailwindcss:build`.

| Tier | Exact state |
| --- | --- |
| Rails, `test/controllers/todays_controller_test.rb` | 11 runs, 88 assertions, 1 failure, 0 errors. `TodaysControllerTest#test_renders_concise_same-day_nutrition_snapshot_context`. Assertion printed at `test/controllers/todays_controller_test.rb:16`: `Expected at least 1 element matching "h2#today-details-heading", found 0.` Rerun hint: `bin/rails test test/controllers/todays_controller_test.rb:4`. Per `a minitest failure line is the assertion location not the test definition`, the rerun hint is the ownership record, not line 16. |
| Brakeman | `bin/brakeman --quiet --no-pager --exit-on-warn --exit-on-error` prints `Brakeman 8.0.5 is not the latest version 8.0.6` and exits non-zero before scanning. This is exit code 5, per `brakeman exit code 5 signals outdated gem version not scan failure`. It is not a scan finding. |
| Serial browser suite | Reviewer-supplied, from review `review_1787779241_654325`: failures confined to `ShoppingListsTest`, `TodayNavigationTest`, and `PlannedMealIngredientReviewsTest`. This plan did not rerun the serial browser suite, so this row is attributed to the reviewer, not independently measured here. |

Rules for the Implementer and Verifier.

- Every test touched by this ticket must pass. A baseline failure is never an excuse for a touched test.
- Any full-suite failure claimed as unrelated requires matched refreshed-base and head arms, per
  `hearth parallel system tests flake so a serial run is the regression oracle`.
- Restore `.gitignore` and run `bin/rails tailwindcss:build` before attributing any failure.

### Runtime path evidence

| Change | Production entry point |
| --- | --- |
| `thumbnail_rendering` and the thumbnail partial | `GET /workout_templates/:id`, `GET /training_sessions/:id`, `GET /training_sessions/:id/edit` |
| Preloads | The same three actions |
| Disclaimer | `GET /exercises`, unconditionally |
| `catalog_credits` | `GET /exercises`, through `Current.household.exercises.from_source_namespace(WorkoutGuide::Import::SOURCE_NAMESPACE)` |
| Offline import path | `GET /exercises`, then `POST /workout_guide_import` plus `WorkoutGuide::ImportJob` |
| README backup documentation | Operator procedure, verified by review of the changed lines |

### Commands

- `bin/rails tailwindcss:build` before every Rails test command
- `bin/rubocop`
- `bin/rails test`
- `bin/system-test-browser bin/rails test:system`
- `bin/brakeman --quiet --no-pager --exit-on-warn --exit-on-error`, expecting the known exit code 5 above

`config/ci.rb` is not changed, so a full `bin/ci` run is not obliged by
`a hearth change to config ci rb obliges a bin ci run`.

## 7. Vault gaps worth capturing

1. Narrow the transform rule. `hearth exercise visuals serve video inline and svg as a download` currently reads
   as a blanket exclusion of Active Storage transforms for every visual type. The true rule after this ticket is:
   exercise detail visuals call no transform, and workout thumbnails use a named variant for `image/png`,
   `image/jpeg`, and `image/webp` only. GIF, SVG, and video never reach a transform anywhere.
2. Capture that `image/gif` is variable in Rails while Hearth deliberately excludes it from the thumbnail variant
   set to preserve animation, so thumbnail code must branch on an explicit content-type list and never on
   `blob.variable?`. This fact was measured on the plan commit.
3. Capture the thumbnail selection rule as a Hearth convention: the first item of the first visual by position,
   with a `bolt` icon placeholder for SVG, video, and visual-free exercises, and the same dark surface the
   exercise detail page applies to unmodified Workout Guide art.
4. Capture that Hearth workout surfaces that render catalog thumbnails must tolerate a nullified
   `TrainingSessionExercise#exercise`, because `Exercise` nullifies that association on destroy.
5. Capture that Hearth offline evidence uses a prepended outbound-network guard plus explicit SQLite adapter and
   Disk service assertions, rather than a claim that no network call occurred.
6. Capture that the Hearth medical tracking disclaimer is unconditional on a catalog surface while source credits
   are conditional, because the disclaimer covers household-authored records too.
7. Note for the pipeline: this run began on a stale worktree that missed two merged dependency branches, and one
   dependency was reported closed while its merge had not yet been fetched. Roles should fetch `origin` and
   fast-forward before treating a closed dependency as absent.

## 8. Smallest-change justification

Every planned line traces to the ticket, a required convention, or cleanup forced by this change.

- The three model additions are predicates and delegators. No new class, PORO, service object, or configuration
  point is introduced.
- One partial serves all three thumbnail surfaces, so no markup is duplicated.
- The transform guard is extracted rather than copied, because four request paths now need it. Duplicating a
  prepend across test files would install the same monkey patch more than once.
- Credits reuse the existing persisted `ATTRIBUTION_FIELDS`. No column, no denormalization, and no bundle file
  reading at request time.
- No new icon, asset, Stimulus controller, or route is added.

## 9. Finding-to-change map for review `review_1787779241_654325`

| Finding | Change |
| --- | --- |
| `finding_1787779241_248674` Always render the exercise tracking disclaimer | Section 3 records human answer `question_1787779055_423059`. Section 4 splits `_tracking_disclaimer` from `_credits` and makes only credits conditional. Section 6 test 9 covers empty, personal-only, and source-linked catalogs. |
| `finding_1787779241_265829` Prove all forbidden transform calls are absent | Section 4 adds the shared `active_storage_transform_guard` helper prepending to both classes for all six combinations. Section 6 tests 5 and 6 drive the real GET actions for GIF, SVG, and both video types, and separately forbid `preview` and `representation` on raster pages. |
| `finding_1787779241_441749` Scope catalog credits to `Current.household` | Section 4 adds the household scoping rule: `catalog_credits` is relation-scoped and its only caller is `Current.household.exercises.from_source`. Section 6 test 10 adds the exclusion proof with `insert_foreign_exercise` and records the model-tier limit. |
| `finding_1787779241_764702` Carry exact baseline failures into implementation | Section 6 adds the baseline table, independently measured here for the Rails and Brakeman rows and attributed to the reviewer for the browser row, plus the three attribution rules. |
| `finding_1787779241_252705` Define and verify complete license presentation | Section 4 adds the credit presentation contract for all seven fields. Section 6 test 9 covers links, blank optional values, bare URLs, and deduplication. |
| `finding_1787779241_130009` Replace unknown query counts with a growth invariant | Section 6 test 8 replaces the deferred absolute counts with an equal-SQL-count invariant across one-row and several-row arms for all four actions, plus a rendered-node correspondence check. U1 no longer defers query counts. |
| `finding_1787779241_101803` Prove a generated thumbnail is usable | Section 6 test 7 follows the representation URL against the Disk service and requires a successful image response, and test 12 adds the browser `naturalWidth` check. Section 1 records the measured 8685-byte variant. |
| `finding_1787779241_543777` Load the required Rails Hotwire Hearth and Elements notes | Section 1 adds `rails-conventions`, `hotwire-patterns`, `hearth-overview`, and `hearth vendors elements locally and has no preview tree`, plus the verification notes now cited throughout, and names `app/views/recipes/index.html.erb` as the local implementation source. |

## 10. Finding-to-change map for review `review_1787779890_852082`

Revision 3 changes.

| Finding | Change |
| --- | --- |
| `finding_1787779890_116176` Limit Workout Guide credits to the Workout Guide namespace | Section 4 renames the rule to "Household and namespace scoping rule for credits" and switches the caller to `Current.household.exercises.from_source_namespace(WorkoutGuide::Import::SOURCE_NAMESPACE)`. It states why `from_source` alone is wrong: it matches every namespace, so a future non-Workout-Guide catalog would render under a Workout Guide heading. Section 6 tests 9 and 10 add namespace inclusion and exclusion cases beside the household cases, and the runtime path table records the namespace scope. |
| `finding_1787779890_307763` Do not require thumbnail nodes on the exercises index | Section 6 test 8 keeps the equal-SQL-growth check on all four actions but splits the paired rendered-row check: thumbnail-node equality applies only to `workout_templates#show`, `training_sessions#show`, and `training_sessions#edit`, while `exercises#index` asserts one rendered disclaimer and the expected credit-row count. This removes the contradiction with the non-scope rule in section 2. |
| `finding_1787779890_685995` Prove the dark thumbnail surface on a production view | Section 6 test 3 adds a rendered assertion on `GET /workout_templates/:id`: `bg-gray-950` present for unmodified Workout Guide source art, absent for personal and for household-modified art. The plan states why the model predicate test alone is insufficient, because a missing class in the partial would leave it green while white art renders on a white card. |
