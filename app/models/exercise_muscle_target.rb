class ExerciseMuscleTarget < ApplicationRecord
  ROLES = %w[primary secondary stabilizer].freeze
  ROLE_PRECEDENCE = ROLES.each_with_index.to_h.freeze

  belongs_to :exercise
  belongs_to :muscle

  enum :role, ROLES.index_with(&:itself), validate: true

  validates :muscle_id, uniqueness: { scope: :exercise_id }

  scope :in_display_order, -> { joins(:muscle).order("muscles.display_position") }
end
