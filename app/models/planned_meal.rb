class PlannedMeal < ApplicationRecord
  belongs_to :household
  belongs_to :person, optional: true
  belongs_to :recipe
  has_many :meals, dependent: :restrict_with_exception
  has_many :shopping_list_item_sources, dependent: :destroy

  after_commit :reconcile_shopping_lists, on: %i[ create update destroy ]

  scope :during, ->(date_range) { where(planned_on: date_range) }
  scope :visible_to, ->(person) { where(person_id: [ nil, person.id ]) }

  validates :planned_on, presence: true
  validate :person_belongs_to_household
  validate :recipe_belongs_to_household
  validate :references_are_available

  attr_accessor :invalid_person_reference

  def converted_meal_for(person)
    meals.loaded? ? meals.detect { |meal| meal.person_id == person.id } : meals.find_by(person:)
  end

  def convertible_by?(person, today: Date.current)
    planned_on <= today && (person_id.nil? || person_id == person.id)
  end

  def convert_for!(person, today: Date.current)
    with_lock do
      existing = meals.find_by(person:)
      return existing if existing
      unless convertible_by?(person, today:)
        errors.add(:base, "This planned meal is not available to convert.")
        raise ActiveRecord::RecordInvalid, self
      end

      meals.create!(
        household: household,
        person: person,
        eaten_on: planned_on,
        meal_items_attributes: [ { source_kind: :recipe, recipe: recipe } ]
      )
    end
  rescue ActiveRecord::RecordNotUnique
    meals.find_by!(person:)
  end

  class << self
    def build_for(household:, planned_on:, recipe_id:, person_id: nil)
      new(
        household: household,
        planned_on: planned_on,
        recipe: household.recipes.find_by(id: recipe_id),
        person: person_id.present? ? household.people.find_by(id: person_id) : nil,
        invalid_person_reference: person_id.present? && !household.people.exists?(id: person_id)
      )
    end
  end

  private
    def reconcile_shopping_lists
      affected_periods.each do |household_id, week_start, create_if_missing|
        household = Household.find_by(id: household_id)
        next unless household

        list = if create_if_missing
          household.shopping_lists.create_or_find_by!(week_start:)
        else
          household.shopping_lists.find_by(week_start:)
        end
        list&.reconcile!
      end
    end

    def affected_periods
      if destroyed?
        return [ [ household_id, planned_on&.beginning_of_week(:monday), false ] ]
      end

      old_household_id, new_household_id = previous_changes["household_id"] || [ household_id, household_id ]
      old_planned_on, new_planned_on = previous_changes["planned_on"] || [ planned_on, planned_on ]

      periods = []
      periods << [ old_household_id, old_planned_on&.beginning_of_week(:monday), false ] if old_planned_on != new_planned_on || old_household_id != new_household_id
      periods << [ new_household_id, new_planned_on&.beginning_of_week(:monday), true ]
      periods.compact.reject { |household_id, week_start, _| household_id.blank? || week_start.blank? }.uniq
    end

    def person_belongs_to_household
      errors.add(:person, "must belong to this household") if person && person.household != household
    end

    def recipe_belongs_to_household
      errors.add(:recipe, "must belong to this household") if recipe && recipe.household != household
    end

    def references_are_available
      errors.add(:person, "is not available") if invalid_person_reference
    end
end
