class ExerciseVisualItem < ApplicationRecord
  IMAGE_CONTENT_TYPES = %w[image/png image/jpeg image/webp image/gif image/svg+xml].freeze
  VIDEO_CONTENT_TYPES = %w[video/mp4 video/webm].freeze
  INLINE_IMAGE_CONTENT_TYPES = %w[image/png image/jpeg image/webp image/gif].freeze
  THUMBNAIL_VARIANT_CONTENT_TYPES = %w[image/png image/jpeg image/webp].freeze
  IMAGE_MAX_BYTES = 10.megabytes
  VIDEO_MAX_BYTES = 50.megabytes

  belongs_to :exercise_visual, inverse_of: :exercise_visual_items
  has_one_attached :file do |attachable|
    attachable.variant :thumb, resize_to_limit: [ 160, 160 ]
  end

  attr_accessor :file_reference_invalid

  validates :position, numericality: { only_integer: true, greater_than: 0 }
  validate :valid_file_reference
  validate :acceptable_file

  def inline_renderable?
    file.attached? && INLINE_IMAGE_CONTENT_TYPES.include?(file.content_type)
  end

  def thumbnail_rendering
    return :placeholder unless file.attached?

    case file.content_type
    when *THUMBNAIL_VARIANT_CONTENT_TYPES
      :variant
    when "image/gif"
      :original
    else
      :placeholder
    end
  end

  def preserve_file_for_form
    change = pending_file_creation
    return self unless change
    return self unless file_blob_acceptable?(change.blob)
    return self if change.blob.persisted?

    change.blob.save!
    change.upload
    self.file = change.blob
    self
  rescue
    change.blob.purge if change&.blob&.persisted? && change.blob.attachments.none?
    raise
  end

  def file_signed_id
    change = pending_file_creation
    change.blob.signed_id if change&.blob&.persisted?
  end

  private
    def valid_file_reference
      errors.add(:file, "is invalid") if ActiveModel::Type::Boolean.new.cast(file_reference_invalid)
    end

    def acceptable_file
      file_blob_acceptable?(file.blob) if file.attached?
      errors.add(:file, "can't be blank") unless file.attached? || pending_file_creation
    end

    def file_blob_acceptable?(blob)
      return false unless blob

      acceptable = true
      allowed_types = allowed_content_types

      unless allowed_types.include?(blob.content_type)
        message = "must be a supported #{exercise_visual&.kind || "visual"} file"
        errors.add(:file, message) unless errors.added?(:file, message)
        acceptable = false
      end

      limit = image_content_type?(blob.content_type) ? IMAGE_MAX_BYTES : VIDEO_MAX_BYTES
      if blob.byte_size > limit
        message = image_content_type?(blob.content_type) ? "must be 10 MB or smaller" : "must be 50 MB or smaller"
        errors.add(:file, message) unless errors.added?(:file, message)
        acceptable = false
      end

      acceptable
    end

    def allowed_content_types
      exercise_visual&.video? ? VIDEO_CONTENT_TYPES : IMAGE_CONTENT_TYPES
    end

    def image_content_type?(content_type)
      IMAGE_CONTENT_TYPES.include?(content_type)
    end

    def pending_file_creation
      change = attachment_changes["file"]
      change if change.is_a?(ActiveStorage::Attached::Changes::CreateOne)
    end
end
