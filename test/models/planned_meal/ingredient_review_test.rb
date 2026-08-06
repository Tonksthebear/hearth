require "test_helper"

class PlannedMeal::IngredientReviewTest < ActiveSupport::TestCase
  MONDAY = Date.new(2026, 8, 10)
  WEDNESDAY = Date.new(2026, 8, 12)
  FRIDAY = Date.new(2026, 8, 14)

  test "a row carries the required amount, the pantry evidence, the queued demand, and the deficit" do
    confirm("Rice", 3, "cup")
    monday = plan(MONDAY, line("Rice", "2", "cup"))
    plan(FRIDAY, line("Rice", "2", "cup"))
    requirement(monday, "Rice").decide!(:on_hand)

    row = review(monday).rows.sole

    assert_equal [ "2 cup", "4 cup", "2 cup", "0 cup" ], [ row.required_amount, row.queued_demand_amount, row.reserved_amount, row.deficit_amount ]
    assert_equal "Confirmed · 3 cup", [ row.pantry_state_label, row.pantry_amount ].compact.join(" · ")
    assert_predicate row, :resolved?
    assert_not_predicate row, :deficit?
  end

  test "the later meal reports the shortfall the earlier one caused" do
    confirm("Rice", 3, "cup")
    monday = plan(MONDAY, line("Rice", "2", "cup"))
    friday = plan(FRIDAY, line("Rice", "2", "cup"))
    requirement(friday, "Rice").decide!(:on_hand)

    row = review(friday).rows.sole

    assert_equal [ "1 cup", "1 cup" ], [ row.reserved_amount, row.deficit_amount ]
    assert_predicate row, :deficit?
    assert_equal [ MONDAY, FRIDAY ], row.contributions.map(&:planned_on)
    assert_equal [ false, true ], row.contributions.map(&:current?)
  end

  test "contributions stay in allocation order rather than date order when a plan is prioritized" do
    confirm("Rice", 1, "cup")
    monday = plan(MONDAY, line("Rice", "1", "cup"))
    friday = plan(FRIDAY, line("Rice", "1", "cup"))
    friday.prioritize_before!(monday)

    assert_equal [ FRIDAY, MONDAY ], review(monday).rows.sole.contributions.map(&:planned_on)
  end

  test "another person's plan keeps its date and amount but surrenders its identity" do
    confirm("Rice", 4, "cup")
    mine = plan(MONDAY, line("Rice", "1", "cup"), person: people(:one))
    plan(WEDNESDAY, line("Rice", "2", "cup"), person: people(:two))
    plan(FRIDAY, line("Rice", "1", "cup"))

    contributions = review(mine).rows.sole.contributions

    assert_equal [ false, true, false ], contributions.map(&:anonymous?)
    assert_nil contributions.second.recipe_title
    assert_equal [ WEDNESDAY, Rational(2) ], [ contributions.second.planned_on, contributions.second.required_quantity ]
    # A household-shared plan carries no person, so it is not another person's plan
    # and stays named — inverting that polarity would hide most of the household.
    assert_equal [ mine.recipe.title, nil, contributions.third.planned_meal.recipe.title ], contributions.map(&:recipe_title)
  end

  test "demand in an incompatible unit is listed but never summed into the total" do
    confirm("Rice", 4, "cup")
    mine = plan(MONDAY, line("Rice", "2", "cup"))
    plan(FRIDAY, line("Rice", "1", "package"))

    row = review(mine).rows.sole

    assert_equal "2 cup", row.queued_demand_amount
    assert_equal 1, row.incompatible_contributions
    assert_predicate row, :incompatible_demand?
    assert_equal 2, row.contributions.size
  end

  test "a not needed or unmeasurable requirement never competes for the ingredient" do
    confirm("Rice", 4, "cup")
    mine = plan(MONDAY, line("Rice", "2", "cup"))
    skipped = plan(FRIDAY, line("Rice", "1", "cup"))
    requirement(skipped, "Rice").decide!(:not_needed)
    free_text = plan(FRIDAY, line("Rice", "to taste", nil))

    row = review(mine).rows.sole

    # Neither the not-needed plan nor the free-text one asked for an amount, so
    # neither appears beside the requirement that did.
    assert_equal [ mine ], row.contributions.map(&:planned_meal)

    unmeasurable = review(free_text).rows.sole
    assert_not_predicate unmeasurable, :measurable?
    assert_equal "to taste", unmeasurable.source_amount
    assert_nil unmeasurable.required_amount
  end

  test "untracked evidence reads as not tracked and incompatible evidence is flagged" do
    untracked = plan(MONDAY, line("Rice", "2", "cup"))
    assert_equal [ "Not tracked", nil ], [ review(untracked).rows.sole.pantry_state_label, review(untracked).rows.sole.pantry_amount ]

    confirm("Rice", 2, "package")
    row = review(untracked).rows.sole

    assert_equal "Confirmed", row.pantry_state_label
    assert_predicate row, :pantry_evidence_incompatible?
  end

  test "a cooked plan closes the review instead of raising" do
    cooked = plan(MONDAY, line("Rice", "2", "cup"))
    cooked.convert_for!(people(:one), today: MONDAY)

    reviewed = review(cooked)

    assert_predicate reviewed, :closed?
    assert_nil reviewed.state_label
    assert_empty reviewed.rows
    assert_not_predicate reviewed, :resolvable?
  end

  test "the plan's own readiness state uses the contract's canonical label" do
    unresolved = plan(MONDAY, line("Rice", "2", "cup"))
    assert_equal "Needs ingredient check", review(unresolved).state_label

    requirement(unresolved, "Rice").decide!(:missing)
    assert_equal "Shopping needed", review(unresolved).state_label

    confirm("Rice", 2, "cup")
    assert_equal "Ready to cook", review(unresolved).state_label
  end

  test "a substitution reports the replacement's name, amount and decision" do
    confirm("Farro", 2, "cup")
    mine = plan(MONDAY, line("Rice", "2", "cup"))
    requirement(mine, "Rice").substitute!(ingredient: ingredient("Farro"), display_quantity: "2", unit: "cup")

    row = review(mine).rows.sole

    assert_predicate row, :substituted?
    assert_equal [ "Farro", "2 cup", "Check ingredient" ], [ row.display_name, row.required_amount, row.decision_label ]

    requirement(mine, "Rice").decide_replacement!(:on_hand)
    assert_equal "On hand", review(mine).rows.sole.decision_label
  end

  test "a repeating fraction is displayed exactly rather than rounded" do
    confirm("Rice", 1, "cup")
    mine = plan(MONDAY, line("Rice", "1/3", "cup"))

    assert_equal "1/3 cup", review(mine).rows.sole.required_amount
  end

  test "a unitless count renders without a unit token" do
    confirm("Eggs", 6, nil)
    mine = plan(MONDAY, line("Eggs", "2", nil))

    assert_equal [ "2", "6" ], [ review(mine).rows.sole.required_amount, review(mine).rows.sole.pantry_amount ]
  end

  private
    def review(planned_meal, person: people(:one))
      PlannedMeal::IngredientReview.new(planned_meal: planned_meal, person: person)
    end

    def line(display_name, display_quantity, unit)
      { display_name: display_name, display_quantity: display_quantity, unit: unit }
    end

    def plan(planned_on, *lines, person: nil, recipe_scale: 1)
      recipe = households(:home).recipes.create!(
        title: "Review plan #{planned_on} #{lines.first.fetch(:display_name)} #{PlannedMeal.count}",
        source_name: "Review fixture",
        provenance_status: :observed
      )
      lines.each_with_index { |attributes, index| recipe.recipe_ingredients.create!(**attributes, position: index + 1) }

      PlannedMeal.create!(
        household: households(:home), recipe: recipe, planned_on: planned_on, person: person, recipe_scale: recipe_scale
      )
    end

    def ingredient(name)
      Ingredient.resolve!(household: households(:home), name: name)
    end

    def confirm(name, quantity, unit)
      PantryItem.for(household: households(:home), ingredient: ingredient(name)).confirm!(
        quantity: quantity, unit: unit, source: "pantry_check", confirmed_by: people(:without_login)
      )
    end

    def requirement(plan, name)
      plan.planned_meal_ingredients.active.find_by!(ingredient: ingredient(name))
    end
end
