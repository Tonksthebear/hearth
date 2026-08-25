require "test_helper"
require_relative "../test_helpers/exercise_visual_test_helper"

class ActiveStoragePolicyTest < ActiveSupport::TestCase
  include ExerciseVisualTestHelper

  test "video analyzers and previewers are disabled" do
    analyzer_names = Rails.application.config.active_storage.analyzers.map(&:name)
    previewer_names = Rails.application.config.active_storage.previewers.map(&:name)

    assert_not_includes analyzer_names, "ActiveStorage::Analyzer::VideoAnalyzer"
    assert_not_includes previewer_names, "ActiveStorage::Previewer::VideoPreviewer"
  end

  test "inline and binary content type policy matches the household visual contract" do
    inline = Rails.application.config.active_storage.content_types_allowed_inline
    binary = Rails.application.config.active_storage.content_types_to_serve_as_binary

    assert_includes inline, "video/mp4"
    assert_includes inline, "video/webm"
    assert_not_includes inline, "image/svg+xml"
    assert_includes binary, "image/svg+xml"
  end

  test "svg blobs force attachment disposition and video blobs stay inline" do
    svg = ActiveStorage::Blob.create_and_upload!(
      io: file_fixture("exercises/icon.svg").open,
      filename: "icon.svg",
      content_type: "image/svg+xml"
    )
    video = ActiveStorage::Blob.create_and_upload!(
      io: file_fixture("exercises/clip.mp4").open,
      filename: "clip.mp4",
      content_type: "video/mp4"
    )

    assert_equal :attachment, svg.forced_disposition_for_serving
    assert_nil video.forced_disposition_for_serving
  ensure
    svg&.purge
    video&.purge
  end
end
