class HabitMetric < ApplicationRecord
  VALUE_TYPES = %w[number duration time_of_day boolean].freeze

  belongs_to :habit
  has_many :person_habit_metrics, dependent: :destroy
  has_many :habit_check_in_measurements, dependent: :restrict_with_exception

  enum :value_type, VALUE_TYPES.index_with(&:itself), validate: true

  validates :key,
    presence: true,
    uniqueness: { scope: :habit_id },
    format: { with: /\A[a-z][a-z0-9_]*\z/, message: "must be a stable lowercase key" }
  validates :label, presence: true
  validates :position, numericality: { only_integer: true, greater_than: 0 }
  validates :unit, presence: true, if: :unit_required?
  validates :unit, absence: true, unless: :unit_required?
  validate :history_schema_is_immutable

  def unit_required?
    number? || duration?
  end

  private
    def history_schema_is_immutable
      return unless persisted? && habit_check_in_measurements.exists?

      %w[key value_type unit].each do |attribute|
        errors.add(attribute, "cannot change after measurements have been recorded") if will_save_change_to_attribute?(attribute)
      end
    end
end
