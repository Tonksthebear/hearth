require "test_helper"

class Person::TodayTest < ActiveSupport::TestCase
  test "orders prepared sections and isolates current-person operational rows" do
    travel_to Time.zone.local(2026, 7, 30, 12) do
      person_habits(:alex_water).habit_check_ins.destroy_all
      today = Person::Today.current(household: households(:home), person: people(:one))

      assert_equal %i[to_do in_progress complete], today.sections.map(&:key)
      assert_includes today.sections.first.items.map(&:title), recipes(:observed_soup).title
      assert_includes today.sections.first.items.map(&:title), habits(:water).name
      assert_includes today.sections.second.items.map(&:title), training_sessions(:draft).snapshot_title
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
        .sections.first.items

      assert_equal :simple_habit, items.find { |item| item.title == "Water" }.kind
      assert_equal :measured_habit, items.find { |item| item.title == "Sauna" }.kind
    end
  end
end
