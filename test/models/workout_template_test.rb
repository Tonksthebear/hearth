require "test_helper"

class WorkoutTemplateTest < ActiveSupport::TestCase
  test "uses template-local provenance including personal" do
    assert_equal %w[verified adapted observed personal], WorkoutTemplate.provenance_statuses.keys
    assert_equal %w[verified adapted observed], Recipe.provenance_statuses.keys

    personal = households(:home).workout_templates.build(title: "Mine", provenance_status: :personal)
    assert_predicate personal, :valid?
  end

  test "mutates three-level form rows with safe coordinates and one-based positions" do
    template = households(:home).workout_templates.build(title: "Composer", provenance_status: :personal)
    template.add_block
    template.add_block
    template.add_prescription(0)
    template.remove_prescription("0:0")
    template.move_block("1:up")

    assert_equal [ 1, 2 ], template.workout_blocks.map(&:position)
    assert_equal [ 1 ], template.workout_blocks.first.exercise_prescriptions.map(&:position)
    assert_equal [ 1 ], template.workout_blocks.second.exercise_prescriptions.reject(&:marked_for_destruction?).map(&:position)
    assert_raises(ArgumentError) { template.add_prescription("missing") }
    assert_raises(ArgumentError) { template.remove_prescription("0:99") }
    assert_raises(ArgumentError) { template.move_block("0:up") }
  end

  test "persisted removals use nested destruction" do
    template = workout_templates(:balanced)
    template.remove_block(0)

    assert_predicate template.workout_blocks.target.first, :marked_for_destruction?
  end

  test "persists reordered blocks through the unique position index" do
    template = workout_templates(:balanced)
    template.move_block("1:up")

    assert template.save
    assert_equal [ "Zone 2", "Strength" ], template.reload.workout_blocks.map(&:title)
    assert_equal [ 1, 2 ], template.workout_blocks.map(&:position)
  end

  test "persists reordered prescriptions through the unique position index" do
    block = workout_blocks(:strength)
    second = block.exercise_prescriptions.create!(
      exercise: exercises(:bike),
      position: 2,
      entry_kind: :interval,
      sets_count: 1,
      work_seconds: 60
    )
    template = block.workout_template
    template.move_prescription("0:1:up")

    assert template.save
    assert_equal [ second.id, exercise_prescriptions(:squat_sets).id ],
      block.reload.exercise_prescriptions.pluck(:id)
    assert_equal [ 1, 2 ], block.exercise_prescriptions.pluck(:position)
  end

  test "database rejects zero and duplicate child positions" do
    assert_raises ActiveRecord::StatementInvalid do
      WorkoutBlock.insert!({
        workout_template_id: workout_templates(:balanced).id,
        position: 0,
        title: "Invalid",
        block_kind: "other",
        dose_class: "none"
      })
    end

    assert_raises ActiveRecord::RecordNotUnique do
      WorkoutBlock.insert!({
        workout_template_id: workout_templates(:balanced).id,
        position: 1,
        title: "Duplicate",
        block_kind: "other",
        dose_class: "none"
      })
    end
  end
end
