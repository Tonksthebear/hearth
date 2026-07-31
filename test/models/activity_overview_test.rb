require "test_helper"

class ActivityOverviewTest < ActiveSupport::TestCase
  test "owns ordered materialized activity sections for the current person and household" do
    travel_to Time.zone.local(2026, 7, 30, 12) do
      overview = ActivityOverview.current(household: households(:home), person: people(:one))

      assert_equal %i[training recovery templates exercises], overview.sections.map(&:key)
      assert_includes overview.sections.first.records.map(&:record), training_sessions(:draft)
      refute_includes overview.sections.first.records.map(&:record), training_sessions(:other_person)
      assert_includes overview.sections.third.records.map(&:record), workout_templates(:balanced)
      assert_includes overview.sections.fourth.records.map(&:record), exercises(:squat)
      assert overview.sections.all? { |section| section.records.frozen? }
    end
  end

  test "fully materialized query count is bounded" do
    travel_to Time.zone.local(2026, 7, 30, 12) do
      assert_queries_count(21) do
        ActivityOverview.current(household: households(:home), person: people(:one))
          .sections
          .flat_map(&:records)
          .each { |item| [ item.title, item.record ] }
      end
    end
  end
end
