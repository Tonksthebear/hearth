require "test_helper"

class HearthMcp::SerializerTest < ActiveSupport::TestCase
  test "recipe detail serializes preloaded normalized ingredient data without queries" do
    recipe = Recipe.includes(recipe_ingredients: :ingredient).find(recipes(:porridge).id)
    serialized = nil

    assert_queries_count(0) do
      serialized = HearthMcp::Serializer.recipe(recipe, detail: true)
    end

    assert_equal recipe.recipe_ingredients.sort_by { |line| [ line.position, line.id ] }.map(&:id),
      serialized.fetch(:ingredients).pluck(:id)
    assert_equal %i[
      id ingredient_id ingredient_name display_name display_quantity
      quantity_numerator quantity_denominator unit notes position
    ], serialized.fetch(:ingredients).first.keys
  end


  test "meal serializes scoped nested event data" do
    meal = Meal.includes(meal_items: [ :recipe, :ingredient, :recipe_feedback, :meal_item_nutrient_values ]).find(meals(:alex_recipe_target_week).id)

    serialized = HearthMcp::Serializer.meal(meal)

    assert_equal meal.id, serialized[:id]
    assert_equal meal.person_id, serialized[:person_id]
    assert_equal "recipe", serialized.dig(:items, 0, :source_kind)
    assert_equal meal_items(:alex_salad).snapshot_label, serialized.dig(:items, 0, :snapshot_label)
    assert_equal recipe_feedbacks(:alex_salad_feedback).body, serialized.dig(:items, 0, :recipe_feedback, :body)
    assert_equal true, serialized.dig(:items, 0, :nutrition_complete)
    protein = serialized.dig(:items, 0, :nutrition).find { |value| value[:key] == "protein" }
    assert_equal "9.2625", protein[:amount]
    assert_equal "estimated", protein[:calculation_kind]
  end

  test "exercise serializes ordered muscle targets and the exact source contract" do
    squat = exercises(:squat)
    serialized = HearthMcp::Serializer.exercise(squat)

    assert_equal %w[glutes quadriceps], serialized.fetch(:muscle_targets).pluck(:muscle_key)
    assert_equal %i[muscle_key name muscle_group role], serialized.fetch(:muscle_targets).first.keys
    assert_equal(
      { muscle_key: "glutes", name: "Glutes", muscle_group: "hips", role: "secondary" },
      serialized.fetch(:muscle_targets).first
    )
    assert_nil serialized[:source_key]
    assert_nil serialized[:source_version]
    assert_nil serialized[:source_removed_at]
    assert_nil serialized[:source_attribution]
    refute serialized.key?(:source_snapshot)
    refute_includes serialized.keys, :creator

    removed_at = Time.utc(2026, 8, 1, 15, 30, 0)
    sourced = households(:home).exercises.create!(
      name: "Sourced hinge",
      modality: :strength,
      movement_pattern: :hinge,
      source_key: "sourced-hinge",
      source_version: "v3",
      source_removed_at: removed_at,
      source_snapshot: {
        "attribution" => { "creator" => "Workout Guide", "license" => "CC BY-SA 4.0" },
        "targets" => { "glutes" => "primary" }
      }
    )
    sourced.replace_muscle_targets!([ { muscle_key: "glutes", role: "primary" } ])
    payload = HearthMcp::Serializer.exercise(sourced)

    assert_equal "sourced-hinge", payload[:source_key]
    assert_equal "v3", payload[:source_version]
    assert_equal "2026-08-01T15:30:00Z", payload[:source_removed_at]
    assert_equal %i[creator creator_url license license_url source_name source_url change_note], payload[:source_attribution].keys
    assert_equal "Workout Guide", payload[:source_attribution][:creator]
    assert_nil payload[:source_attribution][:creator_url]
    assert_nil payload[:source_attribution][:change_note]
    refute payload.key?(:source_snapshot)
    Exercise::SourceMerge::ATTRIBUTION_FIELDS.each do |field|
      refute payload.key?(field.to_sym)
    end

    personal = households(:home).exercises.create!(
      name: "Personal carry",
      modality: :strength,
      movement_pattern: :carry
    )
    empty = HearthMcp::Serializer.exercise(personal)
    assert_nil empty[:source_removed_at]
    assert_nil empty[:source_attribution]
    assert_empty empty[:muscle_targets]
  end
end
