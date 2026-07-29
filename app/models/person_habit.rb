class PersonHabit < ApplicationRecord
  WEEKDAYS = %w[sunday monday tuesday wednesday thursday friday saturday].freeze

  belongs_to :person
  belongs_to :habit
  has_many :person_habit_metrics, dependent: :destroy
  has_many :habit_check_ins, dependent: :destroy

  accepts_nested_attributes_for :person_habit_metrics, reject_if: :all_blank

  validates :habit_id, uniqueness: { scope: :person_id }
  validates :position, numericality: { only_integer: true, greater_than: 0 }
  validate :habit_belongs_to_person_household

  before_validation :assign_position, on: :create
  after_initialize :default_schedule, if: :new_record?

  scope :active, -> { where(active: true) }
  scope :in_display_order, -> { order(:position, :id) }

  def scheduled_on?(date)
    public_send(WEEKDAYS.fetch(date.wday))
  end

  def ensure_target_rows
    existing_metric_ids = person_habit_metrics.map(&:habit_metric_id)
    habit.habit_metrics.each do |metric|
      person_habit_metrics.build(habit_metric: metric) unless existing_metric_ids.include?(metric.id)
    end
    self
  end

  private
    def assign_position
      self.position ||= person.person_habits.maximum(:position).to_i + 1
    end

    def default_schedule
      WEEKDAYS.each { |weekday| self[weekday] = true if self[weekday].nil? }
    end

    def habit_belongs_to_person_household
      return unless person && habit
      errors.add(:habit, "must belong to the same household") unless habit.household_id == person.household_id
    end
end
