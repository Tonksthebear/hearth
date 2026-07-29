require "test_helper"

class PersonTest < ActiveSupport::TestCase
  test "weekly dose targets are nullable positive integers" do
    person = people(:one)

    assert person.update(
      weekly_structured_minutes_target: nil,
      weekly_strength_sessions_target: 2,
      weekly_zone2_minutes_target: 90,
      weekly_vigorous_minutes_target: 20
    )

    person.weekly_structured_minutes_target = 0
    assert_not person.valid?
  end
  test "belongs to a household and may own one login" do
    person = people(:one)

    assert_equal households(:home), person.household
    assert_equal users(:one), person.user
  end

  test "requires a name" do
    person = Person.new(household: households(:home), name: "")

    assert_not person.valid?
    assert_includes person.errors[:name], "can't be blank"
  end

  test "does not require a login" do
    person = people(:without_login)

    assert_predicate person, :persisted?
    assert_nil person.user
  end
end
