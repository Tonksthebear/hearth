require "application_system_test_case"
require_relative "../test_helpers/exercise_visual_test_helper"

class ExerciseVisualPlaybackTest < ApplicationSystemTestCase
  include ExerciseVisualTestHelper

  test "cycles workout guide frames from the library path and keeps one visible frame" do
    exercise = create_workout_guide_sequence_exercise(name: "Cycling hinge")

    sign_in_via_browser users(:one)
    open_exercise_from_library(exercise)

    frames = all("[data-frame-sequence-target='frame']", visible: :all)
    assert_equal 3, frames.size
    assert_selector "[data-controller='frame-sequence']", count: 1
    assert_selector "[data-frame-sequence-target='frame']:not([data-hidden])", count: 1
    initial_src = visible_frame_src
    assert page.has_no_selector?("[data-frame-sequence-target='frame']:not([data-hidden])[src='#{initial_src}']", wait: 3)
    assert_selector "[data-frame-sequence-target='frame']:not([data-hidden])", count: 1
  end

  test "playback cadence follows the server rendered interval attribute" do
    exercise = create_workout_guide_sequence_exercise(name: "Slow hinge", frame_interval_ms: 1500)

    sign_in_via_browser users(:one)
    open_exercise_from_library(exercise)

    container = find("[data-controller='frame-sequence']")
    assert_equal "1500", container["data-frame-sequence-interval-value"]
    deltas = observed_frame_deltas(seconds: 4.0)
    assert deltas.any? { |delta| (delta - 1.5).abs < 0.45 }, "expected a 1500ms cadence, got #{deltas.inspect}"
  end

  test "keyboard controls play pause step wrap and never disable" do
    exercise = create_workout_guide_sequence_exercise(name: "Keyboard hinge")

    sign_in_via_browser users(:one)
    open_exercise_from_library(exercise)

    play = find("button[aria-label='Play animation']")
    pause = find("button[aria-label='Pause animation']")
    previous = find("button[aria-label='Previous frame']")
    nxt = find("button[aria-label='Next frame']")
    [ play, pause, previous, nxt ].each { |control| assert_not control.disabled? }

    pause.send_keys(:enter)
    assert_playing false
    first_src = visible_frame_src

    play.send_keys(:space)
    assert_playing true
    pause.send_keys(:space)
    assert_playing false

    nxt.send_keys(:enter)
    assert_playing false
    second_src = visible_frame_src
    assert_not_equal first_src, second_src

    previous.send_keys(:enter)
    assert_equal first_src, visible_frame_src

    nxt.send_keys(:space)
    nxt.send_keys(:space)
    nxt.send_keys(:space)
    assert_equal first_src, visible_frame_src

    previous.send_keys(:space)
    previous.send_keys(:space)
    previous.send_keys(:space)
    assert_equal first_src, visible_frame_src
    assert_no_selector "[role='img'] button"
  end

  test "class attributes stay unchanged across play and pause" do
    exercise = create_workout_guide_sequence_exercise(name: "Immutable classes")

    sign_in_via_browser users(:one)
    open_exercise_from_library(exercise)

    container = find("[data-controller='frame-sequence']")
    frames = all("[data-frame-sequence-target='frame']", visible: :all)
    container_class = container[:class]
    frame_classes = frames.map { |frame| frame[:class] }

    find("button[aria-label='Pause animation']").send_keys(:enter)
    assert_playing false
    assert_equal container_class, container[:class]
    assert_equal frame_classes, all("[data-frame-sequence-target='frame']", visible: :all).map { |frame| frame[:class] }
  end

  test "turbo disconnect leaves detached frames invariant and reconnects one player" do
    exercise = create_workout_guide_sequence_exercise(name: "Turbo hinge")
    interval_ms = exercise.exercise_visuals.sole.frame_interval_ms

    sign_in_via_browser users(:one)
    open_exercise_from_library(exercise)

    page.execute_script("window.__frameLeakProbe = document.querySelector('[data-controller=\"frame-sequence\"]')")
    click_link_and_wait_for_path "Back to exercises", exercises_path
    assert_equal false, page.evaluate_script("document.contains(window.__frameLeakProbe)")
    assert_detached_frame_invariant(interval_ms:)

    click_link_and_wait_for_path exercise.name, exercise_path(exercise)
    assert_playing true
    assert_selector "[data-controller='frame-sequence']", count: 1
  end

  test "reduced motion starts paused and keeps the visible frame invariant" do
    exercise = create_workout_guide_sequence_exercise(name: "Quiet hinge")
    interval_ms = exercise.exercise_visuals.sole.frame_interval_ms

    emulate_media([ { name: "prefers-reduced-motion", value: "reduce" } ])
    sign_in_via_browser users(:one)
    open_exercise_from_library(exercise)

    assert_playing false
    assert_frame_invariant(find("[data-controller='frame-sequence']"), interval_ms:)
  ensure
    reset_emulated_media
  end

  test "dark source surface applies only to unmodified workout guide art" do
    exercise = create_workout_guide_sequence_exercise(name: "Surface hinge")

    emulate_media([ { name: "prefers-color-scheme", value: "light" } ])
    sign_in_via_browser users(:one)
    open_exercise_from_library(exercise)
    untouched_background = computed_background(find("[role='img'][aria-label$='animation frames.']"))

    visual = exercise.exercise_visuals.sole
    item = ExerciseVisualItem.find(visual.sorted_items.first.id)
    previous_digest = item.file.blob.checksum
    item.file.attach(visual_upload("animated.gif", "image/gif"))
    item.reload
    assert_not_equal previous_digest, item.file.blob.checksum
    assert_not ExerciseVisual.find(visual.id).unmodified_source_art?

    click_link_and_wait_for_path "Back to exercises", exercises_path
    click_link_and_wait_for_path exercise.name, exercise_path(exercise)
    replaced_background = computed_background(find("[role='img'][aria-label$='animation frames.']"))
    assert_not_equal untouched_background, replaced_background
  ensure
    reset_emulated_media
  end

  test "covers still image gif video svg attribution and both color schemes" do
    exercise = create_catalog_exercise(name: "Kind coverage")
    add_image_visual(exercise, alt_text: "Still image")
    add_image_visual(exercise, filename: "animated.gif", content_type: "image/gif", alt_text: "Animated gif")
    add_image_visual(exercise, filename: "icon.svg", content_type: "image/svg+xml", alt_text: "SVG download")
    add_video_visual(exercise, alt_text: "Inline video")
    exercise.source_snapshot = {
      "attribution" => {
        "creator" => "Workout Guide",
        "license" => "CC BY-SA 4.0",
        "source_name" => "Workout Guide"
      }
    }
    exercise.exercise_muscle_targets.build(muscle: muscles(:chest), role: :primary)
    exercise.save!
    svg_path = rails_storage_proxy_path(exercise.exercise_visuals.find_by!(alt_text: "SVG download").exercise_visual_items.sole.file)
    gif_path = rails_storage_proxy_path(exercise.exercise_visuals.find_by!(alt_text: "Animated gif").exercise_visual_items.sole.file)

    emulate_media([ { name: "prefers-color-scheme", value: "light" } ])
    sign_in_via_browser users(:one)
    open_exercise_from_library(exercise)

    assert_selector "img[alt='Still image']"
    assert_selector "img[alt='Animated gif'][src*='#{File.basename(gif_path)}']"
    assert_no_selector "[role='group'][aria-label='Animated gif playback controls']"
    assert_selector "video[aria-label='Inline video']"
    assert_selector "a[href='#{svg_path}']"
    assert_no_selector "img[src='#{svg_path}']"
    assert_text "Workout Guide"
    assert_selector "svg[aria-hidden='true']"
    assert_selector "section[aria-label='Muscle targets']", text: /Chest/
    refute find("section[aria-label='Muscle targets']")["aria-hidden"]

    emulate_media([ { name: "prefers-color-scheme", value: "dark" } ])
    visit_and_wait_for_path exercise_path(exercise)
    assert_selector "svg[aria-hidden='true']"
    assert_selector "section[aria-label='Muscle targets']", text: /Primary/
  ensure
    reset_emulated_media
  end

  private
    def open_exercise_from_library(exercise)
      click_link_and_wait_for_path "Activities", activity_week_path
      click_link_and_wait_for_path "Library", activity_library_path
      click_link_and_wait_for_path "All exercises", exercises_path, match: :first
      click_link_and_wait_for_path exercise.name, exercise_path(exercise)
    end

    def visible_frame_src(container = nil)
      if container
        container.find("[data-frame-sequence-target='frame']:not([data-hidden])", visible: :all)[:src]
      else
        find("[data-frame-sequence-target='frame']:not([data-hidden])")[:src]
      end
    end

    def assert_playing(expected)
      value = expected ? "true" : "false"
      assert_selector "[data-controller='frame-sequence'][data-playing='#{value}']"
      assert_selector "button[aria-label='Play animation'][aria-pressed='#{value}']"
      assert_selector "button[aria-label='Pause animation'][aria-pressed='#{expected ? "false" : "true"}']"
    end

    def assert_frame_invariant(container, interval_ms:)
      samples = []
      gap = (interval_ms / 4.0) / 1000.0
      13.times do
        samples << visible_frame_src(container)
        sleep gap
      end
      assert_equal 1, samples.uniq.size, "expected one distinct frame src, got #{samples.uniq.inspect}"
    end

    def assert_detached_frame_invariant(interval_ms:)
      samples = []
      gap = (interval_ms / 4.0) / 1000.0
      13.times do
        samples << page.evaluate_script(<<~JS)
          (() => {
            const root = window.__frameLeakProbe
            const frame = Array.from(root.querySelectorAll('[data-frame-sequence-target="frame"]'))
              .find((node) => !node.hasAttribute("data-hidden"))
            return frame ? frame.getAttribute("src") : null
          })()
        JS
        sleep gap
      end
      assert_equal 1, samples.uniq.size, "expected one distinct detached frame src, got #{samples.uniq.inspect}"
    end

    def observed_frame_deltas(seconds:)
      samples = []
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      loop do
        src = visible_frame_src
        now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        samples << [ now, src ] if samples.empty? || samples.last[1] != src
        break if now - started >= seconds

        sleep 0.05
      end
      samples.each_cons(2).map { |(first_at, _), (second_at, _)| second_at - first_at }
    end

    def emulate_media(features)
      page.driver.browser.execute_cdp("Emulation.setEmulatedMedia", features: features)
    end

    def reset_emulated_media
      page.driver.browser.execute_cdp("Emulation.setEmulatedMedia", features: [])
    end

    def computed_background(element)
      page.evaluate_script("getComputedStyle(arguments[0]).backgroundColor", element)
    end
end
