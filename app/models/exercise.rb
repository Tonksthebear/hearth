class Exercise < ApplicationRecord
  MODALITIES = %w[strength cardio mobility balance recovery mixed other].freeze
  MOVEMENT_PATTERNS = %w[
    squat hinge lunge horizontal_push vertical_push horizontal_pull vertical_pull
    carry core locomotion_cardio mobility balance other
  ].freeze

  belongs_to :household
  has_many :exercise_prescriptions, dependent: :restrict_with_exception
  has_many :training_session_exercises, dependent: :nullify

  enum :modality, MODALITIES.index_with(&:itself), prefix: true, validate: true
  enum :movement_pattern, MOVEMENT_PATTERNS.index_with(&:itself), prefix: true, validate: true

  validates :name, presence: true, uniqueness: { scope: :household_id }
end
