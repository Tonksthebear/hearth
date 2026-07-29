require "test_helper"

class MealLogTest < ActiveSupport::TestCase
  test "requires exactly one of recipe or ad hoc description" do
    log = MealLog.new(
      household: households(:home),
      person: people(:one),
      eaten_on: Date.new(2026, 7, 27)
    )

    assert_not log.valid?
    assert_includes log.errors[:base], "Choose a recipe or describe an ad hoc meal, but not both."

    log.recipe = recipes(:porridge)
    log.ad_hoc_description = "Toast"
    assert_not log.valid?

    log.ad_hoc_description = ""
    assert_predicate log, :valid?
  end

  test "ad hoc logging does not mutate the recipe catalog" do
    assert_no_difference [ "Recipe.count", "RecipeIngredient.count" ] do
      MealLog.create!(
        household: households(:home),
        person: people(:one),
        eaten_on: Date.new(2026, 7, 27),
        ad_hoc_description: "Ate while traveling"
      )
    end
  end

  test "week scope excludes other people and adjacent dates" do
    week = MealWeek.for(
      household: households(:home),
      person: people(:one),
      date: "2026-07-27"
    )

    assert_includes week.meal_logs, meal_logs(:alex_recipe_target_week)
    assert_includes week.meal_logs, meal_logs(:alex_ad_hoc_target_week)
    refute_includes week.meal_logs, meal_logs(:sam_recipe_target_week)
    refute_includes week.meal_logs, meal_logs(:alex_adjacent_week)
  end

  test "requires person and recipe associations to match the household" do
    other_household = Household.new(name: "Other")
    other_person = other_household.people.build(name: "Other person")
    other_recipe = other_household.recipes.build(
      title: "Other recipe",
      source_name: "Test",
      provenance_status: :observed
    )
    log = MealLog.new(
      household: households(:home),
      person: other_person,
      recipe: other_recipe,
      eaten_on: Date.new(2026, 7, 27)
    )

    assert_not log.valid?
    assert_includes log.errors[:person], "must belong to this household"
    assert_includes log.errors[:recipe], "must belong to this household"
  end
end
