require "test_helper"

class MealTest < ActiveSupport::TestCase
  test "supports ordered recipe ingredient and free text items without changing the catalog" do
    meal = Meal.build_for(
      household: households(:home),
      person: people(:one),
      attributes: {
        eaten_on: Date.new(2026, 7, 31),
        notes: "Dinner after training",
        meal_items_attributes: [
          { source_kind: :recipe, recipe: recipes(:porridge), portion_amount: 1.5, portion_unit: "servings" },
          { source_kind: :ingredient, ingredient: ingredients(:rolled_oats), substitutions: "No milk" },
          { source_kind: :free_text, snapshot_label: "Airport sandwich", notes: "Half" }
        ]
      }
    )

    assert_no_difference [ "Recipe.count", "Ingredient.count" ] do
      meal.save!
    end

    assert_equal [ 1, 2, 3 ], meal.meal_items.map(&:position)
    assert_equal %w[recipe ingredient free_text], meal.meal_items.map(&:source_kind)
    assert_equal "Airport sandwich", meal.meal_items.third.snapshot_label
    assert_equal "Dinner after training", meal.notes
  end

  test "normalizes positions after removing an item" do
    meal = meals(:alex_recipe_target_week)
    meal.add_item(:free_text).snapshot_label = "Fruit"
    meal.add_item(:free_text).snapshot_label = "Tea"
    meal.save!

    meal.remove_item(1)
    meal.save!

    assert_equal [ 1, 2 ], meal.reload.meal_items.map(&:position)
    assert_equal [ "Salad", "Tea" ], meal.meal_items.map(&:snapshot_label)
  end

  test "snapshot labels survive later catalog changes" do
    item = meal_items(:alex_salad)
    original = item.snapshot_label

    item.recipe.update!(title: "Renamed salad")

    assert_equal original, item.reload.snapshot_label
    assert_equal original, item.meal.description
  end

  test "known time must match the required reporting date" do
    meal = meals(:alex_recipe_target_week)

    meal.eaten_at = Time.zone.local(2026, 1, 5, 8, 30)

    assert_not meal.valid?
    assert_includes meal.errors[:eaten_at], "must be on the date eaten"

    meal.eaten_at = Time.zone.local(meal.eaten_on.year, meal.eaten_on.month, meal.eaten_on.day, 8, 30)
    assert_predicate meal, :valid?
  end

  test "rejects sources and people from another household" do
    other_household = Household.new(name: "Other")
    other_person = other_household.people.build(name: "Other person")
    other_recipe = other_household.recipes.build(title: "Other recipe", provenance_status: :personal)
    meal = Meal.new(household: households(:home), person: other_person, eaten_on: Date.new(2026, 7, 31))
    meal.meal_items.build(source_kind: :recipe, recipe: other_recipe, position: 1)

    assert_not meal.valid?
    assert_includes meal.errors[:person], "must belong to this household"
    assert_includes meal.meal_items.first.errors[:recipe], "must belong to this household"
  end

  test "week scope includes and excludes the correct people and dates" do
    week = MealWeek.for(household: households(:home), person: people(:one), date: "2026-07-27")

    assert_includes week.meals, meals(:alex_recipe_target_week)
    assert_includes week.meals, meals(:alex_ad_hoc_target_week)
    refute_includes week.meals, meals(:sam_recipe_target_week)
    refute_includes week.meals, meals(:alex_adjacent_week)
  end

  test "deleting one recipe item removes only its event feedback" do
    first = meal_items(:alex_salad)
    other_meal = people(:one).meals.create!(
      household: households(:home), eaten_on: Date.new(2026, 7, 30),
      meal_items_attributes: [ { source_kind: :recipe, recipe: recipes(:salad), recipe_feedback_attributes: { body: "Keep this one" } } ]
    )

    assert_difference "RecipeFeedback.count", -1 do
      first.destroy!
    end

    assert_equal "Keep this one", other_meal.meal_items.first.recipe_feedback.reload.body
  end
end
