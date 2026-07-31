module TargetMeasurements
  extend ActiveSupport::Concern

  class_methods do
    def validates_target_measurements(require_primary: true, **attributes)
      class_attribute :target_measurement_attributes, instance_writer: false, default: attributes

      validate :target_rep_range_is_ordered
      validate :primary_target_matches_performance_kind if require_primary
      validate :target_distance_unit_matches_amount
      validate :target_count_unit_matches_count
      validate :heart_rate_target_is_complete_and_ordered
    end
  end

  private
    def target_measurement(name)
      public_send(target_measurement_attributes.fetch(name))
    end

    def target_measurement_attribute(name)
      target_measurement_attributes.fetch(name)
    end

    def target_rep_range_is_ordered
      minimum = target_measurement(:rep_min)
      maximum = target_measurement(:rep_max)
      if minimum && maximum && maximum < minimum
        errors.add(target_measurement_attribute(:rep_max), "must be at least the minimum reps")
      end
    end

    def primary_target_matches_performance_kind
      case target_measurement(:performance_kind)
      when "reps"
        if target_measurement(:rep_min).blank? && target_measurement(:rep_max).blank?
          errors.add(:base, "Specify a rep target.")
        end
      when "duration"
        add_required_target_error(:work_seconds, "is required for duration work")
      when "distance"
        add_required_target_error(:distance_amount, "is required for distance work")
      when "count"
        add_required_target_error(:count, "is required for count work")
      when "interval"
        add_required_target_error(:work_seconds, "is required for intervals")
        add_required_target_error(:rest_seconds, "is required for intervals")
      end
    end

    def add_required_target_error(name, message)
      errors.add(target_measurement_attribute(name), message) if target_measurement(name).blank?
    end

    def target_distance_unit_matches_amount
      return if target_measurement(:distance_amount).present? == target_measurement(:distance_unit).present?

      errors.add(target_measurement_attribute(:distance_unit), "must be provided with target distance")
    end

    def target_count_unit_matches_count
      return if target_measurement(:count).present? == target_measurement(:count_unit).present?

      errors.add(target_measurement_attribute(:count_unit), "must be provided with target count")
    end

    def heart_rate_target_is_complete_and_ordered
      minimum = target_measurement(:heart_rate_min)
      maximum = target_measurement(:heart_rate_max)
      unit = target_measurement(:heart_rate_unit)
      values_present = minimum.present? || maximum.present?
      unit_attribute = target_measurement_attribute(:heart_rate_unit)

      errors.add(unit_attribute, "must be provided with a heart-rate target") if values_present && unit.blank?
      errors.add(unit_attribute, "requires a heart-rate target") if unit.present? && !values_present
      if minimum && maximum && maximum < minimum
        errors.add(target_measurement_attribute(:heart_rate_max), "must be at least the minimum heart rate")
      end
    end
end
