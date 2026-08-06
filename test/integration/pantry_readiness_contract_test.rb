require "test_helper"
require "yaml"

class PantryReadinessContractTest < ActiveSupport::TestCase
  CONTRACT_PATH = Rails.root.join("test/fixtures/files/pantry_readiness/acceptance_scenarios.yml")
  DOCUMENT_PATH = Rails.root.join("docs/pantry-readiness-product-contract.md")

  TOP_LEVEL_KEYS = %w[contract_version scenarios vocabulary].freeze
  VOCABULARY_KEYS = %w[ingredient_decisions readiness_states].freeze
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
    cold_switch_first_reconcile
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

    assert_not_empty readiness
    assert_not_empty decisions
    assert_equal readiness, fixture_vocabulary("readiness_states")
    assert_equal decisions, fixture_vocabulary("ingredient_decisions")

    assert_enum_usage("readiness_state", readiness.keys)
    assert_enum_usage("ingredient_decision", decisions.keys)
  end

  test "scenarios pin the cross-ticket acceptance outcomes" do
    assert_equal "needs_ingredient_check", scenario("unknown_stock").dig("expected", "meal", "readiness_state")
    assert_empty scenario("unknown_stock").dig("expected", "generated_shopping_rows")

    partial_meals = scenario("partial_stock_prioritizes_earlier_meal").dig("expected", "meals").index_by { |meal| meal.fetch("id") }
    assert_equal({ "readiness_state" => "ready_to_cook", "allocated_quantity" => 2 }, partial_meals.fetch("monday_chili").except("id"))
    assert_equal 1, partial_meals.fetch("friday_chili").fetch("deficit_quantity")
    assert_equal "shopping_needed", partial_meals.fetch("friday_chili").fetch("readiness_state")

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

    cutover = scenario("cold_switch_first_reconcile").fetch("expected")
    assert_equal [ "untouched_open" ], cutover.fetch("removed_row_ids")
    assert_equal %w[edited_open manual_row], cutover.fetch("surviving_open_row_ids")
    assert_equal [ "completed_row" ], cutover.fetch("surviving_non_open_row_ids")
    assert_empty cutover.fetch("generated_shopping_rows")
    assert_equal false, cutover.fetch("pantry_confirmation_created")
    assert_equal true, cutover.fetch("temporary_empty_generated_state_allowed")
  end

  private
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
