require "test_helper"

class Person::TodayTest < ActiveSupport::TestCase
  test "orders prepared sections and isolates current-person operational rows" do
    travel_to Time.zone.local(2026, 7, 30, 12) do
      person_habits(:alex_water).habit_check_ins.destroy_all
      today = Person::Today.current(household: households(:home), person: people(:one))

      assert_equal %i[in_progress up_next done], today.sections.map(&:key)
      sections = today.sections.index_by(&:key)
      assert_includes sections.fetch(:up_next).items.map(&:title), recipes(:observed_soup).title
      assert_includes sections.fetch(:up_next).items.map(&:title), habits(:water).name
      assert_includes sections.fetch(:in_progress).items.map(&:title), training_sessions(:in_progress).snapshot_title
      refute today.sections.flat_map(&:items).any? { |item| item.title == training_sessions(:other_person).snapshot_title }
      assert_predicate today.sections, :frozen?
      assert today.sections.all? { |section| section.items.frozen? }
    end
  end

  test "distinguishes simple and measured habit actions" do
    travel_to Time.zone.local(2026, 7, 30, 12) do
      person_habits(:alex_water).habit_check_ins.destroy_all
      person_habits(:alex_sauna).habit_check_ins.destroy_all
      items = Person::Today.current(household: households(:home), person: people(:one))
        .sections.find { |section| section.key == :up_next }.items

      assert_equal :simple_habit, items.find { |item| item.title == "Water" }.kind
      assert_equal :measured_habit, items.find { |item| item.title == "Sauna" }.kind
    end
  end

  test "fully materialized query count is bounded" do
    travel_to Time.zone.local(2026, 7, 30, 12) do
      # habit_check_ins fixtures move with Date.current; rebuild one in-window row so the
      # bound still exercises the check-in path after calendar day advances.
      pinned_on = Date.new(2026, 7, 30)
      water = person_habits(:alex_water)
      water.habit_check_ins.where(checked_on: pinned_on).delete_all
      water.habit_check_ins.create!(checked_on: pinned_on)
      ActiveRecord::Base.connection.clear_query_cache

      assert_queries_count(15) do
        Person::Today.current(household: households(:home), person: people(:one))
          .sections
          .flat_map(&:items)
          .each { |item| [ item.title, item.description, item.status ] }
      end
    end
  end


  test "prepares concise signed-in-person nutrition from snapshots" do
    today = Person::Today.new(household: households(:home), person: people(:one), date: Date.new(2026, 7, 27))

    assert_equal "estimated", today.nutrition_summary.status
    assert_equal BigDecimal("9.2625"), today.nutrition_summary.totals.find { |total| total.key == "protein" }.amount
  end
end
