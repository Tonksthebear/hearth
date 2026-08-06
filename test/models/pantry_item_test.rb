require "test_helper"

class PantryItemTest < ActiveSupport::TestCase
  FIRST_OBSERVATION = Time.utc(2026, 8, 9, 18)
  SECOND_OBSERVATION = Time.utc(2026, 8, 10, 18)

  test "an untracked ingredient reads as unknown without a persisted row" do
    item = pantry_item_for(:carrots)

    assert_not item.persisted?
    assert_predicate item, :unknown?
    assert_nil item.quantity
    assert_nil item.available_quantity
  end

  test "confirmation stores a reduced exact amount under the canonical unit" do
    item = nil

    assert_difference "PantryItem.count", 1 do
      item = pantry_item_for(:carrots).confirm!(
        quantity: "2/6",
        unit: "Cups",
        source: "pantry_check",
        confirmed_by: people(:without_login),
        confirmed_at: FIRST_OBSERVATION
      )
    end

    item.reload
    assert_predicate item, :confirmed?
    assert_equal [ 1, 3 ], [ item.quantity_numerator, item.quantity_denominator ]
    assert_equal Rational(1, 3), item.quantity
    assert_equal Rational(1, 3), item.available_quantity
    assert_equal "cup", item.unit
    assert_equal "pantry_check", item.confirmation_source
    assert_equal people(:without_login), item.confirmed_by
    assert_equal FIRST_OBSERVATION, item.confirmed_at
  end

  test "confirmation updates the household's single row for an ingredient and refreshes provenance" do
    assert_no_difference "PantryItem.count" do
      pantry_item_for(:rolled_oats).confirm!(
        quantity: "1 1/2",
        unit: "cup",
        source: "purchase",
        confirmed_by: people(:two),
        confirmed_at: SECOND_OBSERVATION
      )
    end

    item = pantry_items(:confirmed_oats).reload
    assert_equal Rational(3, 2), item.quantity
    assert_equal "purchase", item.confirmation_source
    assert_equal people(:two), item.confirmed_by
    assert_equal SECOND_OBSERVATION, item.confirmed_at
  end

  test "a blank confirmation unit is canonical generic count" do
    item = pantry_item_for(:carrots).confirm!(
      quantity: 2,
      source: "pantry_check",
      confirmed_by: people(:without_login)
    )

    assert_equal "count", item.reload.unit
    assert_predicate item.measurement, :known?
    assert_equal :count, item.measurement.family
  end

  test "confirmation rejects an unrecognized unit even when the quantity parses" do
    item = pantry_item_for(:carrots)

    assert_equal Rational(2), Ingredient::Measurement.new(quantity: "2", unit: "pinch").quantity
    assert_no_difference "PantryItem.count" do
      assert_raises ActiveRecord::RecordInvalid do
        item.confirm!(quantity: "2", unit: "pinch", source: "pantry_check", confirmed_by: people(:without_login))
      end
    end
  end

  test "confirmation rejects an unparseable or non-positive amount" do
    [ [ "some", "cup" ], [ "0", "cup" ], [ "-2", "cup" ] ].each do |quantity, unit|
      assert_no_difference "PantryItem.count" do
        assert_raises ActiveRecord::RecordInvalid, "#{quantity} #{unit} should not confirm" do
          pantry_item_for(:carrots).confirm!(quantity: quantity, unit: unit, source: "pantry_check", confirmed_by: people(:without_login))
        end
      end
    end
  end

  test "qualitative observations drop the amount and refresh provenance" do
    {
      mark_low!: "low",
      mark_out!: "out",
      clear!: "unknown"
    }.each do |command, state|
      item = pantry_items(:confirmed_oats)
      item.update_columns(state: "confirmed", quantity_numerator: 4, quantity_denominator: 1, unit: "cup")

      item.public_send(command, source: "pantry_check", confirmed_by: people(:without_login), confirmed_at: SECOND_OBSERVATION)
      item.reload

      assert_equal state, item.state
      assert_nil item.quantity
      assert_nil item.unit
      assert_equal SECOND_OBSERVATION, item.confirmed_at
      assert_equal people(:without_login), item.confirmed_by
    end
  end

  test "out supplies zero while low and unknown stay unresolved" do
    assert_equal Rational(0), pantry_items(:out_lettuce).available_quantity
    assert_nil pantry_items(:low_blueberries).available_quantity
    assert_nil pantry_item_for(:carrots).available_quantity
  end

  test "clearing an untracked ingredient is a no-op" do
    item = pantry_item_for(:carrots)

    assert_no_difference "PantryItem.count" do
      assert_equal false, item.clear!(source: "pantry_check", confirmed_by: people(:without_login))
    end
    assert_not item.persisted?
  end

  test "adjustment applies an exact signed delta in a compatible unit" do
    item = pantry_items(:confirmed_oats)

    item.adjust!(delta: Rational(-3, 2), unit: "cup", source: "pantry_check", confirmed_by: people(:without_login))
    assert_equal Rational(5, 2), item.reload.quantity

    item.adjust!(delta: Rational(-16), unit: "tbsp", source: "pantry_check", confirmed_by: people(:without_login))
    assert_equal Rational(3, 2), item.reload.quantity

    item.adjust!(delta: Rational(1, 2), unit: "cup", source: "purchase", confirmed_by: people(:without_login))
    assert_equal Rational(2), item.reload.quantity
    assert_equal "cup", item.unit
    assert_predicate item, :confirmed?
  end

  test "a zero adjustment re-confirms the same amount with fresh provenance" do
    item = pantry_items(:confirmed_oats)

    item.adjust!(delta: Rational(0), unit: "cup", source: "purchase", confirmed_by: people(:two), confirmed_at: SECOND_OBSERVATION)
    item.reload

    assert_predicate item, :confirmed?
    assert_equal Rational(4), item.quantity
    assert_equal "purchase", item.confirmation_source
    assert_equal people(:two), item.confirmed_by
    assert_equal SECOND_OBSERVATION, item.confirmed_at
  end

  test "an adjustment to exactly zero becomes an amount-less out row" do
    item = pantry_items(:confirmed_oats)

    item.adjust!(delta: Rational(-4), unit: "cup", source: "pantry_check", confirmed_by: people(:without_login))
    item.reload

    assert_predicate item, :out?
    assert_nil item.quantity
    assert_nil item.unit
    assert_equal Rational(0), item.available_quantity
  end

  test "an adjustment below zero is rejected atomically" do
    item = pantry_items(:confirmed_oats)
    before = observation_snapshot(item)

    assert_raises ActiveRecord::RecordInvalid do
      item.adjust!(delta: Rational(-5), unit: "cup", source: "purchase", confirmed_by: people(:two), confirmed_at: SECOND_OBSERVATION)
    end

    assert_equal before, observation_snapshot(item.reload)
  end

  test "an adjustment in an unknown or incompatible unit is rejected atomically" do
    [ [ Rational(-1), "pinch" ], [ Rational(-1), "g" ], [ Rational(-1), nil ] ].each do |delta, unit|
      item = pantry_items(:confirmed_oats)
      before = observation_snapshot(item)

      assert_raises ActiveRecord::RecordInvalid, "#{delta} #{unit.inspect} should not adjust" do
        item.adjust!(delta: delta, unit: unit, source: "purchase", confirmed_by: people(:two))
      end

      assert_equal before, observation_snapshot(item.reload)
    end
  end

  test "generic count and container families are not interchangeable for adjustment" do
    item = pantry_item_for(:carrots).confirm!(quantity: 2, unit: "can", source: "pantry_check", confirmed_by: people(:without_login))

    assert_raises ActiveRecord::RecordInvalid do
      item.adjust!(delta: Rational(-1), unit: "count", source: "pantry_check", confirmed_by: people(:without_login))
    end

    counted = pantry_item_for(:blueberries)
    counted.confirm!(quantity: 2, source: "pantry_check", confirmed_by: people(:without_login))

    assert_raises ActiveRecord::RecordInvalid do
      counted.adjust!(delta: Rational(-1), unit: "can", source: "pantry_check", confirmed_by: people(:without_login))
    end
  end

  test "adjustment requires an exact Rational delta rather than a signed string or float" do
    [ "-2", -2, -2.0, nil ].each do |delta|
      assert_raises ArgumentError, "#{delta.inspect} should not be accepted as a delta" do
        pantry_items(:confirmed_oats).adjust!(delta: delta, unit: "cup", source: "pantry_check", confirmed_by: people(:without_login))
      end
    end
  end

  test "the shared measurement parser still treats a negative quantity as unknown" do
    [ "-2", "-1/2", -2, Rational(-2) ].each do |quantity|
      assert_predicate Ingredient::Measurement.new(quantity: quantity, unit: "cup"), :unknown?
    end
  end

  test "adjustment is rejected from every non-confirmed state" do
    [ pantry_items(:low_blueberries), pantry_items(:out_lettuce), pantry_item_for(:carrots) ].each do |item|
      before = item.persisted? ? observation_snapshot(item) : nil

      assert_no_difference "PantryItem.count" do
        assert_raises ActiveRecord::RecordInvalid, "#{item.state} should not adjust" do
          item.adjust!(delta: Rational(1), unit: "cup", source: "pantry_check", confirmed_by: people(:without_login))
        end
      end

      assert_equal before, observation_snapshot(item.reload) if before
    end
  end

  test "an adjustment recomputes from the committed row instead of a stale copy" do
    first = pantry_items(:confirmed_oats)
    stale = PantryItem.find(first.id)

    first.adjust!(delta: Rational(-1), unit: "cup", source: "pantry_check", confirmed_by: people(:without_login))
    stale.adjust!(delta: Rational(-1), unit: "cup", source: "pantry_check", confirmed_by: people(:without_login))

    assert_equal Rational(2), first.reload.quantity
    assert_equal Rational(2), stale.reload.quantity
  end

  test "the household keeps one row per ingredient in Rails and in the database" do
    pantry_item_for(:carrots).confirm!(quantity: 1, unit: "head", source: "pantry_check", confirmed_by: people(:without_login))

    assert_no_difference "PantryItem.count" do
      pantry_item_for(:carrots).confirm!(quantity: 2, unit: "head", source: "pantry_check", confirmed_by: people(:without_login))
    end

    duplicate = PantryItem.new(
      household: households(:home),
      ingredient: ingredients(:carrots),
      confirmed_by: people(:without_login),
      state: :low,
      confirmation_source: "pantry_check",
      confirmed_at: Time.current
    )
    assert_not duplicate.valid?

    assert_raises ActiveRecord::RecordNotUnique do
      PantryItem.insert!(pantry_row(ingredient: ingredients(:carrots), state: "low"))
    end
  end

  test "a lost create race applies the observation to the winning row" do
    item = pantry_item_for(:carrots)
    PantryItem.insert!(pantry_row(ingredient: ingredients(:carrots), state: "low"))
    winner = nil

    assert_no_difference "PantryItem.count" do
      with_stubbed_method(item, :save!, ->(*) { raise ActiveRecord::RecordNotUnique, "index_pantry_items_on_household_id_and_ingredient_id" }) do
        winner = item.mark_out!(source: "pantry_check", confirmed_by: people(:without_login))
      end
    end

    assert_not_same item, winner
    assert_predicate winner.reload, :out?
    assert_equal winner.id, PantryItem.where(ingredient: ingredients(:carrots)).sole.id
  end

  test "the database rejects invalid states and incoherent amounts" do
    connection = ActiveRecord::Base.connection
    confirmed = pantry_items(:confirmed_oats)
    qualitative = pantry_items(:low_blueberries)

    assert_raises ActiveRecord::StatementInvalid do
      PantryItem.insert!(pantry_row(ingredient: ingredients(:carrots), state: "stocked"))
    end
    assert_raises ActiveRecord::StatementInvalid do
      connection.execute("UPDATE pantry_items SET quantity_denominator = NULL WHERE id = #{confirmed.id}")
    end
    assert_raises ActiveRecord::StatementInvalid do
      connection.execute("UPDATE pantry_items SET quantity_denominator = 0 WHERE id = #{confirmed.id}")
    end
    assert_raises ActiveRecord::StatementInvalid do
      connection.execute("UPDATE pantry_items SET quantity_numerator = 0 WHERE id = #{confirmed.id}")
    end
    assert_raises ActiveRecord::StatementInvalid do
      connection.execute("UPDATE pantry_items SET unit = NULL WHERE id = #{confirmed.id}")
    end
    assert_raises ActiveRecord::StatementInvalid do
      connection.execute("UPDATE pantry_items SET unit = 'cup' WHERE id = #{qualitative.id}")
    end
    assert_raises ActiveRecord::StatementInvalid do
      connection.execute("UPDATE pantry_items SET quantity_numerator = 1, quantity_denominator = 1 WHERE id = #{qualitative.id}")
    end
  end

  test "a confirmed row assigned directly must carry a recognized canonical unit" do
    [ "pinch", "cups", "COUNT", "" ].each do |unit|
      item = confirmed_row(unit: unit)

      assert_not item.valid?, "#{unit.inspect} should not be a storable confirmed unit"
      assert_includes item.errors[:unit], "must be a recognized canonical unit"
      assert_raises ActiveRecord::RecordInvalid do
        item.save!
      end
    end
  end

  test "a confirmed row assigned directly accepts every canonical unit label" do
    labels = Ingredient::Measurement::UNITS.each_value.map(&:normalized_label) + [ PantryItem::GENERIC_COUNT_UNIT ]

    labels.each do |unit|
      item = confirmed_row(unit: unit)

      assert_predicate item, :valid?, "#{unit.inspect} is a canonical label and should be storable: #{item.errors.full_messages}"
      assert_equal unit, item.measurement.normalized_label
    end
  end

  test "the model rejects an unknown state before the database sees it" do
    item = pantry_items(:low_blueberries)
    item.state = "stocked"

    assert_not item.valid?
    assert_predicate item.errors[:state], :any?
  end

  test "the ingredient and the confirmer must belong to the pantry household" do
    other_household = Household.new(name: "Other")
    item = PantryItem.new(
      household: households(:home),
      ingredient: other_household.ingredients.build(name: "Other oats"),
      confirmed_by: other_household.people.build(name: "Other person"),
      state: :low,
      confirmation_source: "pantry_check",
      confirmed_at: Time.current
    )

    assert_not item.valid?
    assert_includes item.errors[:ingredient], "must belong to this household"
    assert_includes item.errors[:confirmed_by], "must belong to this household"
  end

  test "household validation loads associations assigned only by foreign key" do
    item = PantryItem.new(state: :low, confirmation_source: "pantry_check", confirmed_at: Time.current)
    item.household_id = households(:home).id + 1
    item.ingredient_id = ingredients(:carrots).id
    item.confirmed_by_id = people(:without_login).id

    assert_not item.association(:ingredient).loaded?
    assert_not item.valid?
    assert_includes item.errors[:ingredient], "must belong to this household"
    assert_includes item.errors[:confirmed_by], "must belong to this household"
  end

  test "household teardown destroys pantry rows before their confirmers" do
    clear_installation
    household = Household.bootstrap(
      household_attributes: { name: "Home" },
      person_attributes: { name: "Owner" },
      user_attributes: { email_address: "owner@example.com", password: "password", password_confirmation: "password" }
    )
    ingredient = household.ingredients.create!(name: "Chickpeas")
    PantryItem.for(household: household, ingredient: ingredient).confirm!(
      quantity: 2,
      unit: "can",
      source: "pantry_check",
      confirmed_by: household.people.sole
    )

    assert_difference({ "Household.count" => -1, "Person.count" => -1, "PantryItem.count" => -1 }) do
      household.destroy!
    end
  end

  test "a confirmer with pantry rows is protected while other people stay deletable" do
    assert_raises ActiveRecord::DeleteRestrictionError do
      people(:without_login).destroy!
    end

    assert_difference "Person.count", -1 do
      people(:one).destroy!
    end
  end

  test "destroying an ingredient destroys its pantry row" do
    ingredient = households(:home).ingredients.create!(name: "Chickpeas")
    PantryItem.for(household: households(:home), ingredient: ingredient).confirm!(
      quantity: 2,
      unit: "can",
      source: "pantry_check",
      confirmed_by: people(:without_login)
    )

    assert_difference "PantryItem.count", -1 do
      ingredient.destroy!
    end
  end

  test "completing shopping work is checklist state only" do
    before = pantry_snapshot

    assert_no_difference "PantryItem.count" do
      shopping_list_items(:manual_milk).complete!
    end

    assert_predicate shopping_list_items(:manual_milk).reload, :completed?
    assert_equal before, pantry_snapshot
  end

  test "logging a planned meal creates no pantry evidence" do
    before = pantry_snapshot

    assert_no_difference "PantryItem.count" do
      planned_meals(:shared_target_week).convert_for!(people(:one), today: Date.new(2026, 7, 31))
    end

    assert_equal before, pantry_snapshot
  end

  test "pantry commands do not reach into recipes, plans, meals, or shopping rows" do
    before = neighbouring_snapshot

    item = pantry_item_for(:carrots).confirm!(quantity: 2, unit: "head", source: "pantry_check", confirmed_by: people(:without_login))
    item.adjust!(delta: Rational(-1), unit: "head", source: "pantry_check", confirmed_by: people(:without_login))
    item.mark_low!(source: "pantry_check", confirmed_by: people(:without_login))
    item.mark_out!(source: "pantry_check", confirmed_by: people(:without_login))
    item.clear!(source: "pantry_check", confirmed_by: people(:without_login))

    assert_equal before, neighbouring_snapshot
  end

  private
    def pantry_item_for(ingredient)
      PantryItem.for(household: households(:home), ingredient: ingredients(ingredient))
    end

    def confirmed_row(unit:)
      PantryItem.new(
        household: households(:home),
        ingredient: ingredients(:carrots),
        confirmed_by: people(:without_login),
        state: :confirmed,
        quantity_numerator: 1,
        quantity_denominator: 1,
        unit: unit,
        confirmation_source: "pantry_check",
        confirmed_at: Time.current
      )
    end

    def observation_snapshot(item)
      item.slice(:state, :quantity_numerator, :quantity_denominator, :unit, :confirmation_source, :confirmed_by_id, :confirmed_at)
    end

    def pantry_snapshot
      PantryItem.order(:id).map { |item| observation_snapshot(item) }
    end

    def neighbouring_snapshot
      [
        Ingredient.order(:id).pluck(:id, :name, :normalized_name, :updated_at),
        Recipe.order(:id).pluck(:id, :updated_at),
        RecipeIngredient.order(:id).pluck(:id, :quantity_numerator, :quantity_denominator, :unit),
        PlannedMeal.order(:id).pluck(:id, :planned_on, :updated_at),
        Meal.order(:id).pluck(:id, :eaten_on, :updated_at),
        ShoppingListItem.order(:id).pluck(:id, :quantity, :unit, :completed_at)
      ]
    end

    def pantry_row(ingredient:, state:)
      {
        household_id: households(:home).id,
        ingredient_id: ingredient.id,
        confirmed_by_id: people(:without_login).id,
        state: state,
        confirmation_source: "pantry_check",
        confirmed_at: Time.current
      }
    end
end
