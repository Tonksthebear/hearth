require "test_helper"
require_relative "../test_helpers/exercise_visual_test_helper"

module ExerciseVisualTransformGuard
  %i[variant preview representation].each do |method_name|
    define_method(method_name) do |*arguments, **keywords, &block|
      if Thread.current[:exercise_visual_forbid_transforms]
        raise "#{self.class.name}##{method_name} must not be called while rendering exercise visuals"
      end

      super(*arguments, **keywords, &block)
    end
  end
end

ActiveStorage::Attachment.prepend(ExerciseVisualTransformGuard)
ActiveStorage::Blob.prepend(ExerciseVisualTransformGuard)

class ExerciseVisualRenderingTest < ActionDispatch::IntegrationTest
  include ExerciseVisualTestHelper

  test "rendering exercise visuals never calls preview representation or variant" do
    exercise = create_catalog_exercise(name: "Rendered visuals")
    add_image_visual(exercise, alt_text: "Rendered image")
    add_frame_sequence(exercise, alt_text: "Rendered sequence")
    add_video_visual(exercise, alt_text: "Rendered video")
    exercise.save!

    sign_in_as users(:one)
    Thread.current[:exercise_visual_forbid_transforms] = true
    get exercise_path(exercise)
    assert_response :success
  ensure
    Thread.current[:exercise_visual_forbid_transforms] = false
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
