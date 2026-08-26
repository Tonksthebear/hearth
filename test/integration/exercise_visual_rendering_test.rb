require "test_helper"
require_relative "../test_helpers/exercise_visual_test_helper"

class ExerciseVisualRenderingTest < ActionDispatch::IntegrationTest
  include ExerciseVisualTestHelper

  test "rendering exercise visuals never calls preview representation or variant" do
    exercise = create_workout_guide_sequence_exercise(
      name: "Rendered visuals",
      targets: [ [ muscles(:chest), :primary ] ]
    )
    add_image_visual(exercise, filename: "animated.gif", content_type: "image/gif", alt_text: "Rendered gif")
    add_image_visual(exercise, filename: "icon.svg", content_type: "image/svg+xml", alt_text: "Rendered svg")
    add_video_visual(exercise, alt_text: "Rendered video")
    exercise.save!

    sign_in_as users(:one)
    with_forbidden_active_storage_transforms(:variant, :preview, :representation) do
      get exercise_path(exercise)
    end
    assert_response :success
    assert_select "[data-controller='frame-sequence']"
    assert_select "[data-muscle-key='chest']"
    assert_select "[role='group']"
    gif_proxy = rails_storage_proxy_path(exercise.exercise_visuals.find_by!(alt_text: "Rendered gif").exercise_visual_items.sole.file)
    svg_proxy = rails_storage_proxy_path(exercise.exercise_visuals.find_by!(alt_text: "Rendered svg").exercise_visual_items.sole.file)
    assert_select "img[src='#{gif_proxy}']"
    assert_select "a[href='#{svg_proxy}']"
    assert_no_match %r{/rails/active_storage/representations/}, response.body
    assert_no_match %r{/rails/active_storage/variants/}, response.body
  end

  test "video blobs serve inline and svg blobs serve as attachments" do
    video = ActiveStorage::Blob.create_and_upload!(
      io: file_fixture("exercises/clip.mp4").open,
      filename: "clip.mp4",
      content_type: "video/mp4"
    )
    svg = ActiveStorage::Blob.create_and_upload!(
      io: file_fixture("exercises/icon.svg").open,
      filename: "icon.svg",
      content_type: "image/svg+xml"
    )

    get rails_storage_proxy_path(video)
    assert_response :success
    assert_equal "video/mp4", response.media_type
    assert_match(/\Ainline/, response.headers["Content-Disposition"])

    get rails_storage_proxy_path(svg)
    assert_response :success
    assert_match(/\Aattachment/, response.headers["Content-Disposition"])
  ensure
    video&.purge
    svg&.purge
  end
end
