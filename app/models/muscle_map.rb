class MuscleMap
  UNMAPPED_KEYS = [].freeze

  def initialize(exercise)
    @exercise = exercise
    @roles_by_key = exercise.ordered_muscle_targets.each_with_object({}) do |target, roles|
      roles[target.muscle.key] = target.role
    end
  end

  def role_for(muscle_key)
    @roles_by_key[muscle_key.to_s]
  end

  def text_targets
    @exercise.ordered_muscle_targets
  end
end
