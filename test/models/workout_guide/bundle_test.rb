require "test_helper"

class WorkoutGuide::BundleTest < ActiveSupport::TestCase
  FIXTURE_ROOT = Rails.root.join("test/fixtures/files/workout_guide")

  test "rejects a frame path that escapes the bundle directory" do
    bundle = WorkoutGuide::Bundle.new(FIXTURE_ROOT)

    error = assert_raises(WorkoutGuide::Bundle::Error) {
      bundle.resolve_asset!("../exercises/frame-a.png")
    }
    assert_includes error.message, "escapes the bundle"
  end

  test "reports a missing checksum entry" do
    bundle = WorkoutGuide::Bundle.new(FIXTURE_ROOT)

    error = assert_raises(WorkoutGuide::Bundle::Error) {
      bundle.resolve_asset!("assets/missing/frame-1.png")
    }
    assert_includes error.message, "missing checksum"
  end

  test "reads the vendored release tag and fixture records" do
    bundle = WorkoutGuide::Bundle.new(FIXTURE_ROOT)

    assert_equal "v1.0.0", bundle.release_tag
    assert_equal %w[bench-press sumo-deadlift cat-cow-stretch], bundle.records.map { |record| record.fetch("slug") }
    assert_equal 64, bundle.checksum_for!("assets/bench-press/frame-1.png").size
  end
end
