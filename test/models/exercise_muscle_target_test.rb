require "test_helper"

class ExerciseMuscleTargetTest < ActiveSupport::TestCase
  test "one exercise can target multiple muscles" do
    assert_equal [ muscles(:quadriceps), muscles(:glutes) ].sort_by(&:key),
      exercises(:squat).muscles.sort_by(&:key)
  end

  test "one muscle can belong to many exercises" do
    assert_equal [ exercises(:bike), exercises(:squat) ].sort_by(&:name),
      muscles(:quadriceps).exercises.sort_by(&:name)
  end

  test "the same exercise and muscle pair cannot appear twice" do
    duplicate = ExerciseMuscleTarget.new(
      exercise: exercises(:squat),
      muscle: muscles(:quadriceps),
      role: :secondary
    )

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:muscle_id], "has already been taken"

    assert_raises ActiveRecord::RecordNotUnique do
      ExerciseMuscleTarget.insert!({
        exercise_id: exercises(:squat).id,
        muscle_id: muscles(:quadriceps).id,
        role: "stabilizer",
        created_at: Time.current,
        updated_at: Time.current
      })
    end
  end

  test "all three roles persist and an unknown role fails at both levels" do
    stabilizer = ExerciseMuscleTarget.create!(
      exercise: exercises(:bike),
      muscle: muscles(:calves),
      role: :stabilizer
    )
    secondary = ExerciseMuscleTarget.create!(
      exercise: exercises(:bike),
      muscle: muscles(:glutes),
      role: :secondary
    )

    assert_equal "primary", exercise_muscle_targets(:bike_quadriceps).role
    assert_equal "secondary", secondary.role
    assert_equal "stabilizer", stabilizer.role
    assert_equal ExerciseMuscleTarget::ROLES, ExerciseMuscleTarget.roles.keys

    unknown = ExerciseMuscleTarget.new(
      exercise: exercises(:bike),
      muscle: muscles(:hamstrings),
      role: "assistant"
    )
    assert_not unknown.valid?
    assert_includes unknown.errors[:role], "is not included in the list"

    assert_raises ActiveRecord::StatementInvalid do
      ExerciseMuscleTarget.insert!({
        exercise_id: exercises(:bike).id,
        muscle_id: muscles(:hamstrings).id,
        role: "assistant",
        created_at: Time.current,
        updated_at: Time.current
      })
    end
  end

  test "destroying an exercise destroys its targets" do
    exercise = households(:home).exercises.create!(
      name: "Disposable hinge",
      modality: :strength,
      movement_pattern: :hinge
    )
    exercise.exercise_muscle_targets.create!(muscle: muscles(:hamstrings), role: :primary)

    assert_difference "ExerciseMuscleTarget.count", -1 do
      exercise.destroy!
    end
  end

  test "destroying a muscle that has targets raises" do
    assert_raises ActiveRecord::DeleteRestrictionError do
      muscles(:quadriceps).destroy!
    end
    assert Muscle.exists?(muscles(:quadriceps).id)
  end

  test "the ordered reader follows muscle display position and nothing else" do
    bike = exercises(:bike)
    bike.exercise_muscle_targets.create!(muscle: muscles(:calves), role: :stabilizer)
    bike.exercise_muscle_targets.create!(muscle: muscles(:glutes), role: :secondary)

    assert_equal %w[glutes quadriceps calves], bike.ordered_muscle_targets.map { |target| target.muscle.key }
    assert_equal %w[glutes quadriceps calves],
      bike.exercise_muscle_targets.in_display_order.map { |target| target.muscle.key }
  end
end
