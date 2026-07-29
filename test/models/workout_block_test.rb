require "test_helper"

class WorkoutBlockTest < ActiveSupport::TestCase
  test "exposes exact structural and dose classifications" do
    assert_equal WorkoutBlock::BLOCK_KINDS, WorkoutBlock.block_kinds.keys
    assert_equal WorkoutBlock::DOSE_CLASSES, WorkoutBlock.dose_classes.keys
  end

  test "requires one-based positions and positive planned duration" do
    block = workout_templates(:balanced).workout_blocks.build(
      position: 0,
      title: "Invalid",
      block_kind: :other,
      dose_class: :none,
      planned_duration_minutes: 0
    )

    assert_not block.valid?
    assert_includes block.errors[:position], "must be greater than 0"
    assert_includes block.errors[:planned_duration_minutes], "must be greater than 0"
  end

  test "prescription positions are protected by database checks and indexes" do
    assert_raises ActiveRecord::StatementInvalid do
      ExercisePrescription.insert!({
        workout_block_id: workout_blocks(:strength).id,
        exercise_id: exercises(:bike).id,
        position: 0,
        entry_kind: "interval",
        sets_count: 1,
        work_seconds: 60
      })
    end

    assert_raises ActiveRecord::RecordNotUnique do
      ExercisePrescription.insert!({
        workout_block_id: workout_blocks(:strength).id,
        exercise_id: exercises(:bike).id,
        position: 1,
        entry_kind: "interval",
        sets_count: 1,
        work_seconds: 60
      })
    end
  end
end
