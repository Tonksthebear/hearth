module TypedHabitValue
  extend ActiveSupport::Concern

  VALUE_COLUMNS = {
    "number" => :number_value,
    "duration" => :duration_value,
    "time_of_day" => :time_of_day_value,
    "boolean" => :boolean_value
  }.freeze

  included do
    validates :number_value, numericality: true, allow_nil: true
    validates :duration_value, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
    validate :value_matches_habit_metric
  end

  def value
    public_send(VALUE_COLUMNS.fetch(habit_metric.value_type))
  end

  def value?
    VALUE_COLUMNS.values.any? { |column| !public_send(column).nil? }
  end

  def display_value
    return if value.nil?

    value_type = habit_metric.value_type
    return value.strftime("%-I:%M %p") if value_type == "time_of_day"
    return value ? "Yes" : "No" if value_type == "boolean"

    value
  end

  private
    def value_matches_habit_metric
      return unless habit_metric

      populated = VALUE_COLUMNS.values.select { |column| !public_send(column).nil? }
      expected = VALUE_COLUMNS.fetch(habit_metric.value_type)
      valid_count = allow_blank_typed_value? ? populated.size <= 1 : populated.size == 1
      return if valid_count && (populated.empty? || populated == [ expected ])

      errors.add(:base, "#{habit_metric.label} must use its #{habit_metric.value_type.humanize.downcase} value.")
    end

    def allow_blank_typed_value?
      false
    end
end
