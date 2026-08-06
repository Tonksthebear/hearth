require "test_helper"
require "yaml"

class PantryReadinessContractTest < ActiveSupport::TestCase
  CONTRACT_PATH = Rails.root.join("test/fixtures/files/pantry_readiness/acceptance_scenarios.yml")
  DOCUMENT_PATH = Rails.root.join("docs/pantry-readiness-product-contract.md")

  TOP_LEVEL_KEYS = %w[contract_version scenarios vocabulary].freeze
  VOCABULARY_KEYS = %w[ingredient_decisions pantry_states readiness_states].freeze
  VOCABULARY_ENTRY_KEYS = %w[label value].freeze
  SCENARIO_KEYS = %w[actions description expected id inputs].freeze
  REQUIRED_SCENARIO_IDS = %w[
    shared_dated_demand
    unknown_stock
    partial_stock_prioritizes_earlier_meal
    substitution
    manual_item_independence
    rescheduling_reallocates_once
    explicit_priority_override
    person_and_household_visibility
    non_blocking_logging
    purchase_confirmation
    free_text_unknown
    free_text_explicit_missing
    compatible_unitless_count
    mixed_unresolved_precedes_deficit
    full_yield_scaled_requirement
    resolved_decision_supersession
    cold_switch_first_reconcile
    pantry_observation_transitions
    pantry_exact_adjustment
  ].freeze

  test "acceptance scenarios have a closed stable shape" do
    assert_equal TOP_LEVEL_KEYS, contract.keys.sort
    assert_equal "pantry_readiness/v1", contract.fetch("contract_version")
    assert_equal VOCABULARY_KEYS, vocabulary.keys.sort

    vocabulary.each_value do |entries|
      assert_kind_of Array, entries
      entries.each do |entry|
        assert_equal VOCABULARY_ENTRY_KEYS, entry.keys.sort
        assert_predicate entry.fetch("value"), :present?
        assert_predicate entry.fetch("label"), :present?
      end
      assert_equal entries.size, entries.pluck("value").uniq.size
    end

    assert_kind_of Array, scenarios
    scenarios.each do |scenario|
      assert_equal SCENARIO_KEYS, scenario.keys.sort, scenario.fetch("id", "scenario without id")
      assert_match(/\A[a-z0-9]+(?:_[a-z0-9]+)*\z/, scenario.fetch("id"))
      assert_predicate scenario.fetch("description"), :present?
      assert_kind_of Hash, scenario.fetch("inputs")
      assert_kind_of Array, scenario.fetch("actions")
      assert_kind_of Hash, scenario.fetch("expected")
    end

    scenario_ids = scenarios.pluck("id")
    assert_equal scenario_ids.size, scenario_ids.uniq.size
    assert_empty REQUIRED_SCENARIO_IDS - scenario_ids
  end

  test "the normative document and scenarios use the same canonical vocabulary" do
    readiness = documented_vocabulary("Canonical readiness states")
    decisions = documented_vocabulary("Canonical ingredient decisions")
    pantry_states = documented_vocabulary("Canonical pantry states")

    assert_not_empty readiness
    assert_not_empty decisions
    assert_not_empty pantry_states
    assert_equal readiness, fixture_vocabulary("readiness_states")
    assert_equal decisions, fixture_vocabulary("ingredient_decisions")
    assert_equal pantry_states, fixture_vocabulary("pantry_states")

    assert_enum_usage("readiness_state", readiness.keys)
    assert_enum_usage("ingredient_decision", decisions.keys)
    assert_enum_usage("pantry_state", pantry_states.keys)

    assert_equal decisions.keys, PlannedMealIngredient.decisions.keys
    assert_equal %w[ unknown on_hand missing ], PlannedMealIngredient.replacement_decisions.keys
    assert_equal pantry_states.keys, PantryItem.states.keys
  end

  test "scenarios pin the cross-ticket acceptance outcomes" do
    shared_meals = scenario("shared_dated_demand").dig("expected", "meals")
    assert_equal %w[monday_rice thursday_rice], shared_meals.pluck("id")
    assert_equal [ 2, 2 ], shared_meals.pluck("allocated_quantity")
    assert_equal [ "ready_to_cook" ], shared_meals.pluck("readiness_state").uniq
    assert_empty scenario("shared_dated_demand").dig("expected", "generated_shopping_rows")

    assert_equal "needs_ingredient_check", scenario("unknown_stock").dig("expected", "meal", "readiness_state")
    assert_empty scenario("unknown_stock").dig("expected", "generated_shopping_rows")

    partial_meals = scenario("partial_stock_prioritizes_earlier_meal").dig("expected", "meals").index_by { |meal| meal.fetch("id") }
    assert_equal({ "readiness_state" => "ready_to_cook", "allocated_quantity" => 2 }, partial_meals.fetch("monday_chili").except("id"))
    assert_equal 1, partial_meals.fetch("friday_chili").fetch("deficit_quantity")
    assert_equal "shopping_needed", partial_meals.fetch("friday_chili").fetch("readiness_state")

    substitution = scenario("substitution").fetch("expected")
    assert_equal "ready_to_cook", substitution.dig("meal", "readiness_state")
    assert_equal "parmesan", substitution.fetch("recipe_requirement_unchanged")
    assert_empty substitution.fetch("generated_shopping_rows")

    manual = scenario("manual_item_independence").fetch("expected")
    assert_equal "needs_ingredient_check", manual.dig("meal", "readiness_state")
    assert_empty manual.fetch("generated_shopping_rows")
    assert_equal false, manual.fetch("pantry_confirmation_created")

    rescheduled = scenario("rescheduling_reallocates_once").fetch("expected")
    assert_equal 1, rescheduled.fetch("total_allocated_quantity")
    assert_equal %w[ready_to_cook shopping_needed], rescheduled.fetch("meals").pluck("readiness_state")

    prioritized = scenario("explicit_priority_override").fetch("expected")
    assert_equal true, prioritized.fetch("planned_dates_unchanged")
    assert_equal 1, prioritized.fetch("total_allocated_quantity")
    assert_equal "friday_roast", prioritized.fetch("meals").find { |meal| meal.fetch("readiness_state") == "ready_to_cook" }.fetch("id")

    visibility = scenario("person_and_household_visibility").fetch("expected")
    assert_equal %w[shared_breakfast alex_lunch], visibility.fetch("selected_person_meals").pluck("id")
    assert_equal [ "sam_dinner" ], visibility.fetch("excluded_selected_person_meal_ids")
    assert_equal %w[alex_lunch sam_dinner], visibility.fetch("household_shopping_source_ids")
    assert_empty visibility.fetch("duplicated_source_ids")

    logging = scenario("non_blocking_logging")
    assert_equal %w[needs_ingredient_check shopping_needed ready_to_cook], logging.dig("inputs", "planned_meals").pluck("readiness_state")
    assert_equal logging.dig("inputs", "planned_meals").pluck("id"), logging.dig("expected", "logged_meal_ids")

    purchase = scenario("purchase_confirmation").fetch("expected")
    assert_equal({ "readiness_state" => "shopping_needed", "pantry_confirmed_quantity" => 0 }, purchase.fetch("after_completion"))
    assert_equal({ "readiness_state" => "ready_to_cook", "pantry_confirmed_quantity" => 2 }, purchase.fetch("after_confirmation"))

    free_text_unknown = scenario("free_text_unknown").fetch("expected")
    assert_equal "needs_ingredient_check", free_text_unknown.dig("meal", "readiness_state")
    assert_empty free_text_unknown.fetch("generated_shopping_rows")

    free_text_missing = scenario("free_text_explicit_missing").fetch("expected")
    assert_equal "shopping_needed", free_text_missing.dig("meal", "readiness_state")
    assert_equal({ "ingredient" => "salt", "display_amount" => "to taste", "aggregation" => "source_specific" }, free_text_missing.fetch("generated_shopping_rows").sole)

    unitless_count = scenario("compatible_unitless_count").fetch("expected")
    assert_equal "ready_to_cook", unitless_count.dig("meal", "readiness_state")
    assert_empty unitless_count.fetch("generated_shopping_rows")

    mixed = scenario("mixed_unresolved_precedes_deficit").fetch("expected")
    assert_equal "needs_ingredient_check", mixed.dig("meal", "readiness_state")
    assert_equal({ "ingredient" => "quinoa", "ingredient_decision" => "missing" }, mixed.fetch("known_deficits").sole)

    scaled = scenario("full_yield_scaled_requirement")
    assert_equal 2, scaled.dig("inputs", "planned_meal", "recipe_scale")
    assert_equal "1", scaled.dig("inputs", "planned_meal", "recipe_line", "display_amount")
    assert_equal({ "ingredient" => "beans", "quantity" => 2, "unit" => "can", "display_amount" => "1" },
      scaled.dig("expected", "requirement"))
    assert_equal "beans", scaled.dig("expected", "recipe_requirement_unchanged")
    assert_equal "ready_to_cook", scaled.dig("expected", "meal", "readiness_state")

    supersession = scenario("resolved_decision_supersession").fetch("expected")
    assert_equal "needs_ingredient_check", supersession.dig("meal", "readiness_state")
    assert_equal [ "unknown" ], supersession.fetch("active_requirements").pluck("ingredient_decision").uniq
    assert_equal({ "ingredient" => "carrots", "quantity" => 2, "unit" => "cup", "supersession_reason" => "requirement_changed" },
      supersession.fetch("superseded_requirements").sole)
    assert_equal false, supersession.fetch("superseded_participate_in_readiness")
    assert_empty supersession.fetch("discarded_untouched_requirements")
    assert_empty PlannedMealIngredient::SUPERSESSION_REASONS &
      fixture_vocabulary("ingredient_decisions").keys

    cutover = scenario("cold_switch_first_reconcile").fetch("expected")
    assert_equal [ "untouched_open" ], cutover.fetch("removed_row_ids")
    assert_equal %w[edited_open manual_row], cutover.fetch("surviving_open_row_ids")
    assert_equal [ "completed_row" ], cutover.fetch("surviving_non_open_row_ids")
    assert_equal false, cutover.fetch("surviving_rows_retain_provenance")
    assert_empty cutover.fetch("generated_shopping_rows")
    assert_equal false, cutover.fetch("pantry_confirmation_created")
    assert_equal true, cutover.fetch("temporary_empty_generated_state_allowed")

    observations = scenario("pantry_observation_transitions").fetch("expected")
    assert_equal 4, observations.dig("after_confirm", "available_quantity")
    assert_equal "2026-08-09T18:00:00Z", observations.dig("after_confirm", "confirmed_at")
    assert_nil observations.dig("after_mark_low", "available_quantity")
    assert_equal 0, observations.dig("after_mark_out", "available_quantity")
    assert_nil observations.dig("after_clear", "available_quantity")
    assert_equal %w[confirmed low out unknown],
      %w[after_confirm after_mark_low after_mark_out after_clear].map { |key| observations.dig(key, "pantry_state") }
    assert_equal %w[2026-08-09T18:00:00Z 2026-08-10T18:00:00Z 2026-08-11T18:00:00Z 2026-08-12T18:00:00Z],
      %w[after_confirm after_mark_low after_mark_out after_clear].map { |key| observations.dig(key, "confirmed_at") }
    assert_equal 1, observations.fetch("pantry_rows")
    assert_equal 0, observations.fetch("untracked_clear_created_rows")

    adjustment = scenario("pantry_exact_adjustment").fetch("expected")
    assert_equal({ "pantry_state" => "confirmed", "quantity" => 2, "unit" => "cup" }, adjustment.fetch("after_same_unit_adjustment"))
    assert_equal({ "pantry_state" => "confirmed", "quantity" => 1, "unit" => "cup" }, adjustment.fetch("after_compatible_unit_adjustment"))
    rejected = adjustment.fetch("rejected_adjustments").sole
    assert_equal "below_zero", rejected.fetch("reason")
    assert_equal [ "confirmed", 1, "cup" ], rejected.values_at("pantry_state", "quantity", "unit_after")
    assert_equal "out", adjustment.dig("after_zeroing_adjustment", "pantry_state")
    assert_equal 0, adjustment.dig("after_zeroing_adjustment", "available_quantity")
    assert_nil adjustment.dig("after_zeroing_adjustment", "quantity")
    assert_equal 1, adjustment.fetch("pantry_rows")
    assert_equal false, adjustment.fetch("automatic_consumption")
  end

  test "unknown stock and manual intent produce no generated shopping work at runtime" do
    limes = recipe_for(title: "Tacos", ingredients: [ { display_quantity: "2", unit: "count", display_name: "Limes" } ])
    tacos = plan_for(recipe: limes, planned_on: WEEK_START)
    manual = ShoppingList.for(household: household, date: WEEK_START).items.create!(name: "Party napkins", user_managed_at: Time.current)

    assert_equal :needs_ingredient_check, readiness_of(tacos)
    assert_empty generated_rows(WEEK_START)

    manual.complete!

    assert_equal :needs_ingredient_check, readiness_of(tacos)
    assert_empty generated_rows(WEEK_START)
    assert manual.reload.completed?
    assert_empty household.pantry_items
  end

  test "partial stock prioritizes the earlier meal and generates only the remaining deficit" do
    confirm_pantry("Beans", quantity: "3", unit: "can")
    chili = recipe_for(title: "Chili", ingredients: [ { display_quantity: "2", unit: "can", display_name: "Beans" } ])
    monday = plan_for(recipe: chili, planned_on: WEEK_START, decision: :on_hand)
    friday = plan_for(recipe: chili, planned_on: WEEK_START + 4.days, decision: :missing)

    assert_equal :ready_to_cook, readiness_of(monday)
    assert_equal :shopping_needed, readiness_of(friday)
    assert_equal [ [ "Beans", "1", "can" ] ], generated_rows(WEEK_START).map { |item| item.values_at(:name, :quantity, :unit) }
    assert_equal [ friday.id ], generated_rows(WEEK_START).sole.planned_meals.ids
  end

  test "explicitly missing free text shops faithfully and stays source specific" do
    soup = recipe_for(title: "Tomato soup", ingredients: [ { display_quantity: "to taste", unit: nil, display_name: "Salt" } ])
    tomato_soup = plan_for(recipe: soup, planned_on: WEEK_START)

    assert_equal :needs_ingredient_check, readiness_of(tomato_soup)
    assert_empty generated_rows(WEEK_START)

    tomato_soup.planned_meal_ingredients.active.sole.decide!(:missing)

    assert_equal :shopping_needed, readiness_of(tomato_soup)
    row = generated_rows(WEEK_START).sole
    assert_equal [ "Salt", "to taste", nil ], row.values_at(:name, :quantity, :unit)
    assert_equal [ "deficit_source", tomato_soup.planned_meal_ingredients.active.sole.id ].to_json, row.generated_key
  end

  test "completion is not stock evidence while an explicit purchase confirmation is" do
    curry = recipe_for(title: "Curry", ingredients: [ { display_quantity: "2", unit: "can", display_name: "Coconut milk" } ])
    plan = plan_for(recipe: curry, planned_on: WEEK_START, decision: :missing)
    row = generated_rows(WEEK_START).sole
    assert_equal [ "Coconut milk", "2", "can" ], row.values_at(:name, :quantity, :unit)

    row.complete!

    assert_equal :shopping_needed, readiness_of(plan)
    assert_equal 0, pantry_confirmed_quantity("Coconut milk")

    PantryItem.for(household: household, ingredient: row.ingredient)
      .record_purchase!(quantity: "2", unit: "can", confirmed_by: household.people.first, confirmed_at: Time.utc(2026, 8, 9, 18))

    assert_equal :ready_to_cook, readiness_of(plan)
    assert_equal 2, pantry_confirmed_quantity("Coconut milk")
    # The deficit is gone; the checked-off row survives only as a tombstone that
    # no longer carries provenance.
    assert_empty generated_rows(WEEK_START).where(completed_at: nil)
    assert row.reload.completed?
    assert_empty row.shopping_list_item_sources
  end

  private
    WEEK_START = Date.new(2026, 8, 10)

    # The pinned scenarios describe a household in isolation, so the fixture
    # household's own plans, lists, and evidence are cleared first.
    def household
      @household ||= households(:home).tap do |home|
        home.planned_meals.destroy_all
        home.shopping_lists.destroy_all
        home.pantry_items.destroy_all
      end
    end

    def recipe_for(title:, ingredients:)
      household.recipes.create!(
        title: title,
        source_name: "Contract",
        provenance_status: :observed,
        recipe_ingredients_attributes: ingredients.map.with_index(1) { |attributes, position| attributes.merge(position:) }
      )
    end

    def plan_for(recipe:, planned_on:, decision: nil)
      plan = household.planned_meals.create!(recipe: recipe, planned_on: planned_on)
      plan.planned_meal_ingredients.active.each { |requirement| requirement.decide!(decision) } if decision
      plan
    end

    def confirm_pantry(name, quantity:, unit:)
      PantryItem.for(household: household, ingredient: Ingredient.resolve!(household: household, name: name))
        .confirm!(quantity: quantity, unit: unit, source: "pantry_check", confirmed_by: household.people.first)
    end

    def pantry_confirmed_quantity(name)
      item = PantryItem.for(household: household, ingredient: Ingredient.resolve!(household: household, name: name))
      item.confirmed? ? item.quantity : 0
    end

    def readiness_of(plan)
      Household::PantryAllocation.new(household).readiness_for(plan)&.state
    end

    def generated_rows(date)
      ShoppingList.for(household: household, date: date).items.where.not(generated_key: nil)
    end

    def contract
      @contract ||= YAML.safe_load(CONTRACT_PATH.read, permitted_classes: [], permitted_symbols: [], aliases: false)
    end

    def vocabulary
      contract.fetch("vocabulary")
    end

    def scenarios
      contract.fetch("scenarios")
    end

    def scenario(id)
      scenarios.find { |scenario| scenario.fetch("id") == id } || flunk("Missing scenario: #{id}")
    end

    def fixture_vocabulary(key)
      vocabulary.fetch(key).to_h { |entry| [ entry.fetch("value"), entry.fetch("label") ] }
    end

    def documented_vocabulary(heading)
      body = DOCUMENT_PATH.read.match(/^## #{Regexp.escape(heading)}\n(?<body>.*?)(?=^## |\z)/m)&.named_captures&.fetch("body", nil)
      assert body, "Missing documented section: #{heading}"

      body.each_line.filter_map do |line|
        match = line.match(/^\|\s*`(?<value>[^`]+)`\s*\|\s*(?<label>[^|]+?)\s*\|/)
        [ match[:value], match[:label] ] if match
      end.to_h
    end

    def assert_enum_usage(key, allowed_values)
      used_values = values_for_key(scenarios, key)
      assert_empty used_values.uniq - allowed_values, "Unknown #{key} values"
      assert_empty allowed_values - used_values.uniq, "Unused documented #{key} values"
    end

    def values_for_key(value, key)
      case value
      when Array
        value.flat_map { |entry| values_for_key(entry, key) }
      when Hash
        value.flat_map do |entry_key, entry_value|
          (entry_key == key ? Array(entry_value) : []) + values_for_key(entry_value, key)
        end
      else
        []
      end
    end
end
