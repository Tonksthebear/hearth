# Everything one household needs to answer a single queued plan's ingredient
# requirements, derived in one pass over Household::PantryAllocation.
#
# Nothing here is persisted or cached: reading the review never reserves stock,
# draws it, or writes a decision. The engine is built once per review so all the
# rows explain the same allocation, which is also why a decision redirects to a
# freshly built page instead of patching one row — a single decision moves the
# household's whole projection.
class PlannedMeal::IngredientReview
  # One queued plan competing for the same ingredient, in the order stock was
  # handed out. A readiness view excludes plans assigned only to another person,
  # so those keep their date and amount but surrender their identity: the plan
  # never exposes a title it is not allowed to show.
  Contribution = Data.define(:planned_meal, :reservation, :anonymous, :current) do
    def anonymous? = anonymous

    def current? = current

    def planned_on = planned_meal.planned_on

    def recipe_title
      planned_meal.recipe.title unless anonymous?
    end

    def required_quantity = reservation.required_quantity

    def reserved_quantity = reservation.reserved_quantity

    def measurement = reservation.measurement
  end

  # One requirement of the plan being reviewed, with the household-wide facts
  # that explain it: what the pantry holds, what the whole queue is asking for,
  # who else is in line, and what is left short.
  Row = Data.define(:reservation, :pantry_item, :contributions, :queued_demand, :incompatible_contributions) do
    def requirement = reservation.requirement

    def ingredient = reservation.ingredient

    def display_name = reservation.display_name

    def measurable? = reservation.measurable?

    def resolved? = reservation.resolved_for_readiness?

    def deficit? = reservation.deficit?

    def substituted? = requirement.substituted?

    def replacement_resolvable? = requirement.replacement_resolvable?

    def decision_label
      substituted? ? requirement.replacement_decision_label : requirement.decision_label
    end

    def required_amount = amount(reservation.required_quantity)

    def reserved_amount = amount(reservation.reserved_quantity)

    def deficit_amount = amount(reservation.deficit_quantity)

    def queued_demand_amount = amount(queued_demand)

    # The authored text a free-text requirement asked for, shown exactly as
    # written because Hearth never coerces it into a number.
    def source_amount
      [ reservation.display_quantity, reservation.measurement.display_unit ].filter_map { |part| part.to_s.strip.presence }.join(" ")
    end

    # An untracked ingredient has no row at all, which the contract treats as
    # exactly the same knowledge as an explicit unknown one.
    def pantry_state_label
      PantryItem::STATE_LABELS.fetch(pantry_item&.state || "unknown")
    end

    def pantry_amount
      amount(pantry_item.quantity, unit: pantry_item.measurement.normalized_label) if pantry_item&.confirmed?
    end

    # A confirmed row in another measurement family supplies nothing and cannot be
    # raised by an "on hand" confirmation without inventing a conversion, so the
    # page says so rather than leaving an unexplained deficit.
    def pantry_evidence_incompatible?
      measurable? && pantry_item&.confirmed? && !reservation.measurement.compatible_with?(pantry_item.measurement)
    end

    # Contributions in another family are listed but never summed, because adding
    # "2 bags" to "500 g" would invent the conversion the contract forbids.
    def incompatible_demand? = incompatible_contributions.positive?

    private
      def amount(quantity, unit: reservation.unit)
        return unless quantity

        [ Ingredient::Measurement.format_quantity(quantity), display_unit(unit) ].compact.join(" ")
      end

      # The generic count group carries no token a household would recognize, so
      # it renders as a bare number the way shopping rows already do.
      def display_unit(unit)
        unit unless unit == Ingredient::Measurement::GENERIC_COUNT.normalized_label
      end
  end

  attr_reader :planned_meal, :person, :readiness, :rows

  def initialize(planned_meal:, person:)
    @planned_meal = planned_meal
    @person = person
    allocation = Household::PantryAllocation.new(planned_meal.household)
    @readiness = allocation.readiness_for(planned_meal)
    @rows = build_rows(allocation)
  end

  # A cooked plan has left the allocation queue and drawn its stock, so there is
  # no projection left to review.
  def closed? = readiness.nil?

  def state_label = readiness&.label

  def resolvable? = planned_meal.ingredient_review_open?

  def awaiting_review? = planned_meal.ingredients_awaiting_review?

  private
    def build_rows(allocation)
      return [].freeze if closed?

      readiness.reservations.map { |reservation| build_row(allocation, reservation) }.freeze
    end

    def build_row(allocation, reservation)
      contributions = allocation.contributions_for(reservation.ingredient).map { |contribution| decorate(contribution) }
      compatible, incompatible = contributions.partition { |contribution| reservation.measurement.compatible_with?(contribution.measurement) }

      Row.new(
        reservation: reservation,
        pantry_item: allocation.pantry_item_for(reservation.ingredient),
        contributions: contributions.freeze,
        queued_demand: queued_demand_for(reservation, compatible),
        incompatible_contributions: incompatible.size
      )
    end

    # Total household demand expressed in the unit the household is looking at, so
    # the number on screen can be compared with the requirement above it.
    def queued_demand_for(reservation, contributions)
      return unless reservation.measurable?

      contributions.sum(Rational(0)) { |contribution| contribution.measurement.convert_to(reservation.measurement.display_unit) }
    end

    # Household-shared plans carry no person, so they are the household's own and
    # stay named. Only a plan assigned to a different person is anonymized.
    def decorate(contribution)
      assigned = contribution.planned_meal.person_id

      Contribution.new(
        planned_meal: contribution.planned_meal,
        reservation: contribution.reservation,
        anonymous: assigned.present? && assigned != person.id,
        current: contribution.planned_meal.id == planned_meal.id
      )
    end
end
