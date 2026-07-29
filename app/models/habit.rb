class Habit < ApplicationRecord
  belongs_to :household
  has_many :habit_metrics, -> { order(:position) }, dependent: :destroy
  has_many :person_habits, dependent: :destroy

  accepts_nested_attributes_for :habit_metrics, allow_destroy: true, reject_if: :all_blank
  before_save :park_changed_metric_positions

  validates :name, presence: true, uniqueness: { scope: :household_id }
  validate :recorded_metrics_are_not_removed

  def add_metric
    habit_metrics.build(position: active_metrics.size + 1, value_type: "number")
    assign_positions_in_target_order
  end

  def remove_metric(index)
    habit_metrics.load_target
    metric = habit_metrics.target.fetch(Integer(index))
    metric.persisted? ? metric.mark_for_destruction : habit_metrics.delete(metric)
    assign_positions_in_target_order
  rescue ArgumentError, IndexError
    raise ArgumentError, "Invalid habit metric row."
  end

  def move_metric(coordinate)
    index, direction = coordinate.to_s.split(":")
    index = Integer(index)
    target = direction == "up" ? index - 1 : index + 1
    records = active_metrics
    raise ArgumentError unless %w[up down].include?(direction)
    raise ArgumentError if index.negative? || target.negative? || index >= records.size || target >= records.size

    records[index], records[target] = records[target], records[index]
    iterator = records.each
    habit_metrics.target.map! { |metric| metric.marked_for_destruction? ? metric : iterator.next }
    assign_positions_in_target_order
  rescue ArgumentError
    raise ArgumentError, "Invalid habit metric row."
  end

  def normalize_positions
    records = active_metrics
    submitted_positions = records.map(&:position)
    if submitted_positions.all? { |position| position.is_a?(Integer) && position.positive? } &&
        submitted_positions.uniq.size == records.size
      ordered = records.sort_by(&:position)
      iterator = ordered.each
      habit_metrics.target.map! { |metric| metric.marked_for_destruction? ? metric : iterator.next }
    end
    assign_positions_in_target_order
    self
  end

  def ensure_form_rows
    add_metric if active_metrics.empty?
    self
  end

  private
    def active_metrics
      habit_metrics.load_target
      habit_metrics.target.reject(&:marked_for_destruction?)
    end

    def assign_positions_in_target_order
      active_metrics.each.with_index(1) { |metric, position| metric.position = position }
      self
    end

    def park_changed_metric_positions
      active_metrics.select { |metric| metric.persisted? && metric.will_save_change_to_position? }.each do |metric|
        desired_position = metric.position
        metric.update_column(:position, metric.id + 1_000_000)
        metric.position = desired_position
      end
    end

    def recorded_metrics_are_not_removed
      habit_metrics.select(&:marked_for_destruction?).each do |metric|
        if metric.habit_check_in_measurements.exists?
          errors.add(:habit_metrics, "#{metric.label} cannot be removed after measurements have been recorded")
        end
      end
    end
end
