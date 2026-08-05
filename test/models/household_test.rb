require "test_helper"

class HouseholdTest < ActiveSupport::TestCase
  setup { clear_installation }

  test "bootstraps a household person and user atomically" do
    household = nil

    assert_difference [ "Household.count", "Person.count", "User.count" ], 1 do
      household = bootstrap
    end

    assert_predicate household, :persisted?
    assert_equal "Owner", household.people.first.name
    assert_equal "owner@example.com", household.users.first.email_address
    assert_equal household, household.users.first.person.household
  end

  test "invalid bootstrap persists none of the identity graph" do
    household = nil

    assert_no_difference [ "Household.count", "Person.count", "User.count" ] do
      household = bootstrap(
        household_attributes: { name: "" },
        person_attributes: { name: "" },
        user_attributes: { email_address: "", password: "", password_confirmation: "" }
      )
    end

    assert_not household.persisted?
    assert_predicate household.errors, :any?
    assert_predicate household.people.first.errors, :any?
    assert_predicate household.people.first.user.errors, :any?
  end

  test "rejects a second household in the model and database" do
    assert_predicate bootstrap, :persisted?

    second = Household.new(name: "Second")
    assert_not second.valid?
    assert_includes second.errors[:installation_key], "has already been taken"

    assert_raises ActiveRecord::RecordNotUnique do
      Household.insert_all!([ household_row(name: "Database second", installation_key: 1) ])
    end
  end

  test "database check constraint rejects another installation key" do
    assert_raises ActiveRecord::StatementInvalid do
      Household.insert_all!([ household_row(name: "Alternate", installation_key: 2) ])
    end
  end

  test "turns a concurrent singleton loss into a renderable error" do
    household = Household.new
    original_new = Household.method(:new)
    Household.define_singleton_method(:new) { |*| household }
    household.define_singleton_method(:save) { raise ActiveRecord::RecordNotUnique, "duplicate" }

    result = bootstrap

    assert_equal household, result
    assert_includes result.errors[:base], "Household setup is no longer available."
  ensure
    Household.define_singleton_method(:new, original_new) if original_new
  end

  test "destroys meal records before their referenced recipes" do
    household = bootstrap
    person = household.people.first
    recipe = household.recipes.create!(
      title: "Teardown meal",
      source_name: "Test",
      provenance_status: :observed
    )
    household.planned_meals.create!(recipe: recipe, planned_on: Date.new(2026, 7, 27))
    household.meals.create!(
      person: person,
      eaten_on: Date.new(2026, 7, 27),
      meal_items_attributes: [ { source_kind: :recipe, recipe: recipe } ]
    )

    assert_difference({
      "Household.count" => -1,
      "PlannedMeal.count" => -1,
      "Meal.count" => -1,
      "MealItem.count" => -1,
      "Recipe.count" => -1
    }) do
      household.destroy!
    end
  end

  private
    def bootstrap(
      household_attributes: { name: "Home" },
      person_attributes: { name: "Owner" },
      user_attributes: { email_address: "owner@example.com", password: "password", password_confirmation: "password" }
    )
      Household.bootstrap(
        household_attributes: household_attributes,
        person_attributes: person_attributes,
        user_attributes: user_attributes
      )
    end

    def household_row(name:, installation_key:)
      { name: name, installation_key: installation_key, created_at: Time.current, updated_at: Time.current }
    end
end
