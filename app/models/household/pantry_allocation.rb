# Deterministic readiness projection over one household's allocation queue.
#
# Nothing here is persisted, cached, or invalidated: every engine recomputes
# reservations from the household's current pantry evidence, plan dates,
# priorities, substitutions, and decisions. That is what makes "recalculate on
# change" structural rather than a callback, and it is why building an engine
# never consumes stock or writes an ingredient decision. Do not memoize one on
# Household — a stale engine would silently break both guarantees.
class Household::PantryAllocation
  # What one active requirement asked for and what the household's confirmed
  # evidence could actually cover. Quantities are exact Rationals in the
  # requirement's own unit; the pantry row keeps its own.
  Reservation = Data.define(:requirement, :ingredient, :decision, :display_quantity, :measurement, :reserved_quantity, :deficit_quantity, :resolved) do
    # Requirement-level resolution: an explicit decision OR definitive household
    # pantry evidence. PlannedMealIngredient#resolved? stays decision-scoped,
    # because the evidence half is only knowable after the allocation pass.
    def resolved_for_readiness? = resolved

    # The name the household would shop for, which is the replacement's once a
    # substitution redirected the requirement.
    def display_name
      requirement.substituted? ? requirement.replacement_display_name : requirement.display_name
    end

    # Whether this requirement can be allocated numerically at all. Free text and
    # unrecognized units stay source-specific and faithful instead.
    def measurable? = measurement.known?

    def required_quantity = measurement.quantity

    def unit = measurement.normalized_label

    # A confirmed shortfall. A measurable requirement is short by whatever it
    # could not reserve, whatever its decision was; a source-specific one is short
    # only when the household explicitly said it is missing.
    def deficit?
      return false unless resolved
      return decision == "missing" unless measurable?

      deficit_quantity.positive?
    end
  end

  # The canonical readiness projection for one queued meal: unresolved first,
  # then a confirmed deficit, then ready.
  Readiness = Data.define(:planned_meal, :state, :reservations) do
    def needs_ingredient_check? = state == :needs_ingredient_check

    def shopping_needed? = state == :shopping_needed

    def ready_to_cook? = state == :ready_to_cook
  end

  attr_reader :household

  def initialize(household)
    @household = household
    # Queried rather than read through the household's association cache, so a
    # fresh engine always sees current evidence with no invalidation step.
    @pantry_items = PantryItem.where(household: household).index_by(&:ingredient_id)
    @reserved = Hash.new(Rational(0))
    @readiness = build_readiness
  end

  # The allocation queue in the order stock was handed out.
  def planned_meals
    @readiness.values.map(&:planned_meal)
  end

  def readiness_for(planned_meal)
    @readiness[planned_meal.id]
  end

  def reservations_for(planned_meal)
    readiness_for(planned_meal)&.reservations || []
  end

  # The exact amount the household's evidence supplies, in the pantry row's own
  # unit. nil when the pantry holds nothing definitive: low, not tracked, and an
  # ingredient with no row at all are all unknown rather than zero.
  def available_for(ingredient)
    @pantry_items[ingredient.id]&.available_quantity
  end

  def reserved_for(ingredient)
    @reserved[ingredient.id]
  end

  def remaining_for(ingredient)
    available = available_for(ingredient)
    available - reserved_for(ingredient) if available
  end

  private
    def build_readiness
      queued_plans.to_h do |plan|
        reservations = active_requirements(plan).map { |requirement| reserve(requirement) }.freeze
        [ plan.id, Readiness.new(planned_meal: plan, state: state_for(reservations), reservations: reservations) ]
      end.freeze
    end

    def queued_plans
      household.planned_meals
        .allocatable
        .in_allocation_order
        .preload(planned_meal_ingredients: [ :ingredient, :replacement_ingredient ])
        .to_a
    end

    # Superseded rows are filtered in Ruby because the association is already
    # loaded; calling .active here would cost one query per plan.
    def active_requirements(plan)
      plan.planned_meal_ingredients.select(&:active?)
    end

    # A substitution redirects the whole requirement — ingredient, amount, unit,
    # and the decision that has to resolve — at the replacement the household
    # chose for this plan. The recipe line and the snapshot itself stay untouched.
    def reserve(requirement)
      substituted = requirement.substituted?
      ingredient = substituted ? requirement.replacement_ingredient : requirement.ingredient
      decision = requirement.effective_decision
      measurement = Ingredient::Measurement.new(
        quantity: substituted ? requirement.replacement_quantity : requirement.quantity,
        unit: substituted ? requirement.replacement_unit : requirement.unit
      )

      # not_needed resolves the requirement without pantry allocation or shopping
      # work, so it demands nothing: it draws no stock and is never short.
      demanded = !requirement.not_needed?
      measurable = measurement.known?
      drawn = draw(ingredient, measurement) if demanded && measurable
      resolved = !drawn.nil? || decision != "unknown"
      required = demanded ? measurement.quantity : Rational(0)
      reserved = drawn || Rational(0) if measurable
      # A shortfall is only confirmed once the requirement resolves; until then
      # the household has not established that anything is missing.
      deficit = required - reserved if measurable && resolved

      Reservation.new(
        requirement: requirement,
        ingredient: ingredient,
        decision: decision,
        display_quantity: substituted ? requirement.replacement_display_quantity : requirement.display_quantity,
        measurement: measurement,
        reserved_quantity: reserved,
        deficit_quantity: deficit,
        resolved: resolved
      )
    end

    # Reserves against the household's confirmed evidence for one ingredient and
    # returns what this requirement got, back in the requirement's own unit. nil
    # means the pantry holds nothing this requirement can draw on, which is also
    # the reason evidence alone cannot resolve it.
    def draw(ingredient, demand)
      pantry = @pantry_items[ingredient.id]
      return unless pantry

      # `out` supplies zero in every unit, so it resolves the requirement as a
      # full deficit with no compatibility question left to answer.
      return Rational(0) if pantry.out?

      supply = pantry.measurement
      # An incompatible family would need an invented count, density, or
      # conversion, so it supplies nothing and resolves nothing.
      return unless pantry.confirmed? && demand.compatible_with?(supply)

      taken = [ demand.normalized_quantity / supply.factor, pantry.available_quantity - @reserved[ingredient.id] ].min
      @reserved[ingredient.id] += taken
      taken * supply.factor / demand.factor
    end

    # A plan with no active requirements has nothing left to check.
    def state_for(reservations)
      return :needs_ingredient_check unless reservations.all?(&:resolved_for_readiness?)
      return :shopping_needed if reservations.any?(&:deficit?)

      :ready_to_cook
    end
end
