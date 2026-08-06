require "test_helper"

# The never-decrease confirmation the ingredient review writes when a household
# marks a requirement on hand. Every branch gets its own case, because each way of
# getting the arithmetic wrong either fabricates stock the household never claimed
# or destroys an observation it did make.
class PantryItemEnsureAtLeastTest < ActiveSupport::TestCase
  test "an untracked ingredient is confirmed at the requested amount" do
    row = ensure_at_least(:carrots, 3, "cup")

    assert_predicate row, :persisted?
    assert_equal [ "confirmed", Rational(3), "cup" ], [ row.state, row.quantity, row.unit ]
    assert_equal [ PantryItem::READINESS_REVIEW_SOURCE, people(:one) ], [ row.confirmation_source, row.confirmed_by ]
  end

  test "a low row is re-established at the requested amount rather than adjusted" do
    pantry_item(:carrots).mark_low!(source: "pantry_check", confirmed_by: people(:without_login))

    assert_equal [ "confirmed", Rational(2) ], state_and_quantity(ensure_at_least(:carrots, 2, "cup"))
  end

  test "an out row is re-established at the requested amount rather than adjusted" do
    pantry_item(:carrots).mark_out!(source: "pantry_check", confirmed_by: people(:without_login))

    assert_equal [ "confirmed", Rational(2) ], state_and_quantity(ensure_at_least(:carrots, 2, "cup"))
  end

  test "a cleared row is re-established at the requested amount rather than adjusted" do
    confirm(:carrots, 9, "cup").clear!(source: "pantry_check", confirmed_by: people(:without_login))

    # The cleared row carries no amount to preserve, so the nine cups the household
    # explicitly stopped asserting do not come back.
    assert_equal [ "confirmed", Rational(2) ], state_and_quantity(ensure_at_least(:carrots, 2, "cup"))
  end

  test "a confirmed row below the requirement is raised in its own unit" do
    confirm(:carrots, 4, "tbsp")

    row = ensure_at_least(:carrots, 1, "cup")

    # One cup is sixteen tablespoons, so the household's chosen unit survives.
    assert_equal [ "confirmed", Rational(16), "tbsp" ], [ row.state, row.quantity, row.unit ]
  end

  test "a confirmed row at or above the requirement keeps its exact quantity and only refreshes provenance" do
    confirmed_at = 3.days.ago.change(usec: 0)
    confirm(:carrots, 6, "cup", confirmed_at: confirmed_at)

    row = ensure_at_least(:carrots, 2, "cup")

    assert_equal [ Rational(6), "cup" ], [ row.quantity, row.unit ]
    assert_equal PantryItem::READINESS_REVIEW_SOURCE, row.confirmation_source
    assert_equal people(:one), row.confirmed_by
    assert_operator row.confirmed_at, :>, confirmed_at
  end

  test "a second call converges instead of compounding" do
    ensure_at_least(:carrots, 2, "cup")
    row = ensure_at_least(:carrots, 2, "cup")

    assert_equal Rational(2), row.quantity
    assert_equal 1, PantryItem.where(ingredient: ingredients(:carrots)).count
  end

  test "a confirmed row in an incompatible family is preserved untouched and reports no write" do
    original = confirm(:carrots, 2, "package")
    snapshot = observation_snapshot(original)

    assert_nil ensure_at_least(:carrots, 500, "g")
    assert_equal snapshot, observation_snapshot(pantry_item(:carrots))
  end

  test "an unmeasurable amount is rejected rather than guessed at" do
    error = assert_raises(ActiveRecord::RecordInvalid) do
      pantry_item(:carrots).ensure_at_least!(
        quantity: "to taste", unit: nil, source: PantryItem::READINESS_REVIEW_SOURCE, confirmed_by: people(:one)
      )
    end

    assert_match "exact positive amount", error.message
    assert_equal 0, PantryItem.where(ingredient: ingredients(:carrots)).count
  end

  test "a unitless count is confirmed in the generic count unit" do
    row = ensure_at_least(:carrots, 2, nil)

    assert_equal [ Rational(2), PantryItem::GENERIC_COUNT_UNIT ], [ row.quantity, row.unit ]
    assert_equal Rational(2), ensure_at_least(:carrots, 1, nil).quantity
  end

  # The regression this command exists for. confirm! replaces rather than merges
  # and neither locks nor reloads, so a target computed before the write would let
  # a stale in-memory instance overwrite a larger committed amount.
  test "a stale in-memory instance cannot lower a larger committed quantity" do
    stale = pantry_item(:carrots).confirm!(
      quantity: 1, unit: "cup", source: "pantry_check", confirmed_by: people(:without_login)
    )
    PantryItem.find(stale.id).confirm!(
      quantity: 6, unit: "cup", source: "pantry_check", confirmed_by: people(:without_login)
    )
    assert_equal Rational(1), stale.quantity, "the in-memory copy must still be stale for this test to mean anything"

    stale.ensure_at_least!(
      quantity: 2, unit: "cup", source: PantryItem::READINESS_REVIEW_SOURCE, confirmed_by: people(:one)
    )

    assert_equal Rational(6), PantryItem.find(stale.id).quantity
  end

  private
    def pantry_item(name)
      PantryItem.for(household: households(:home), ingredient: ingredients(name))
    end

    def confirm(name, quantity, unit, confirmed_at: Time.current)
      pantry_item(name).confirm!(
        quantity: quantity, unit: unit, source: "pantry_check", confirmed_by: people(:without_login), confirmed_at: confirmed_at
      )
    end

    def ensure_at_least(name, quantity, unit)
      pantry_item(name).ensure_at_least!(
        quantity: quantity, unit: unit, source: PantryItem::READINESS_REVIEW_SOURCE, confirmed_by: people(:one)
      )
    end

    def state_and_quantity(item)
      [ item.state, item.quantity ]
    end

    def observation_snapshot(item)
      item.slice(:state, :quantity_numerator, :quantity_denominator, :unit, :confirmation_source, :confirmed_by_id, :confirmed_at)
    end
end
