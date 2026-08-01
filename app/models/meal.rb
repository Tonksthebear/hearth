class Meal < ApplicationRecord
  belongs_to :household
  belongs_to :person
  belongs_to :planned_meal, optional: true
  has_many :meal_items, -> { order(:position) }, dependent: :destroy, inverse_of: :meal

  accepts_nested_attributes_for :meal_items, allow_destroy: true, reject_if: :all_blank

  scope :during, ->(date_range) { where(eaten_on: date_range) }

  validates :eaten_on, presence: true
  validate :eaten_at_matches_eaten_on
  validate :person_belongs_to_household
  validate :planned_meal_belongs_to_household
  validate :planned_meal_is_visible_to_person
  validate :contains_an_item

  before_validation :normalize_positions

  class << self
    def build_for(household:, person:, attributes: {})
      new(attributes.merge(household: household, person: person))
    end
  end

  def description
    meal_items.reject(&:marked_for_destruction?).map(&:snapshot_label).compact_blank.to_sentence
  end

  def add_item(source_kind = :free_text)
    item = meal_items.build(source_kind:, position: active_items.size + 1)
    item.build_recipe_feedback if item.recipe?
    normalize_positions
    item
  end

  def remove_item(index)
    item = meal_items.to_a.fetch(Integer(index))
    item.persisted? ? item.mark_for_destruction : meal_items.target.delete(item)
    normalize_positions
    self
  rescue ArgumentError, IndexError
    self
  end

  def normalize_positions
    active_items.each.with_index(1) { |item, position| item.position = position }
    self
  end

  def ensure_form_item
    add_item if active_items.empty?
    self
  end

  def feedback_items
    active_items.select(&:recipe?)
  end

  private
    def active_items
      meal_items.reject(&:marked_for_destruction?)
    end

    def person_belongs_to_household
      errors.add(:person, "must belong to this household") if person && person.household != household
    end

    def planned_meal_belongs_to_household
      errors.add(:planned_meal, "must belong to this household") if planned_meal && planned_meal.household != household
    end

    def planned_meal_is_visible_to_person
      return unless planned_meal && person
      return if planned_meal.person_id.nil? || planned_meal.person_id == person.id

      errors.add(:planned_meal, "is not available to this person")
    end

    def contains_an_item
      errors.add(:meal_items, "must include at least one item") if active_items.empty?
    end

    def eaten_at_matches_eaten_on
      return unless eaten_at && eaten_on

      errors.add(:eaten_at, "must be on the date eaten") unless eaten_at.to_date == eaten_on
    end
end
