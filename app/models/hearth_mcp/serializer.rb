module HearthMcp
  class Serializer
    ORIGIN = "hearth_database"
    TIMEZONE = "UTC"

    class << self
      def envelope(data)
        {
          origin: ORIGIN,
          timezone: TIMEZONE,
          generated_at: Time.current.utc.iso8601,
          data: data
        }
      end

      def person(record)
        {
          id: record.id,
          name: record.name,
          weekly_dose_targets: {
            structured_minutes: record.weekly_structured_minutes_target,
            strength_sessions: record.weekly_strength_sessions_target,
            zone2_minutes: record.weekly_zone2_minutes_target,
            vigorous_minutes: record.weekly_vigorous_minutes_target
          }
        }
      end

      def recipe(record, detail: false)
        result = {
          id: record.id,
          title: record.title,
          description: record.description,
          yield: record.yield,
          provenance_status: record.provenance_status,
          source_name: record.source_name,
          source_url: record.source_url
        }
        if detail
          result[:ingredients] = record.recipe_ingredients.sort_by { |line| [ line.position, line.id ] }.map do |line|
            {
              id: line.id,
              ingredient_id: line.ingredient_id,
              ingredient_name: line.ingredient.name,
              display_name: line.display_name,
              display_quantity: line.display_quantity,
              quantity_numerator: line.quantity_numerator,
              quantity_denominator: line.quantity_denominator,
              unit: line.unit,
              notes: line.notes,
              position: line.position
            }
          end
        end
        result
      end

      def planned_meal(record)
        {
          id: record.id,
          planned_on: record.planned_on.iso8601,
          person_id: record.person_id,
          scope: record.person_id ? "person" : "household",
          recipe: recipe(record.recipe)
        }
      end

      def meal(record)
        {
          id: record.id,
          eaten_on: record.eaten_on.iso8601,
          eaten_at: record.eaten_at&.utc&.iso8601,
          person_id: record.person_id,
          planned_meal_id: record.planned_meal_id,
          description: record.description,
          notes: record.notes,
          items: record.meal_items.map do |item|
            {
              id: item.id,
              position: item.position,
              source_kind: item.source_kind,
              snapshot_label: item.snapshot_label,
              recipe: item.recipe && recipe(item.recipe),
              ingredient: item.ingredient && { id: item.ingredient_id, name: item.ingredient.name },
              portion_amount: item.portion_amount&.to_s,
              portion_unit: item.portion_unit,
              substitutions: item.substitutions,
              notes: item.notes,
              recipe_feedback: item.recipe_feedback && { id: item.recipe_feedback.id, body: item.recipe_feedback.body }
            }
          end
        }
      end

      def exercise(record)
        record.attributes.symbolize_keys.slice(:id, :name, :modality, :movement_pattern, :equipment, :guidance)
      end

      def workout_template(record)
        record.attributes.symbolize_keys.slice(
          :id, :title, :description, :provenance_status, :source_name, :source_url
        )
      end

      def training_session(record)
        {
          id: record.id,
          person_id: record.person_id,
          workout_template_id: record.workout_template_id,
          title: record.snapshot_title,
          performed_on: record.performed_on.iso8601,
          started_at: record.started_at&.utc&.iso8601,
          completed_at: record.completed_at&.utc&.iso8601,
          status: record.completed? ? "completed" : "in_progress",
          provenance_status: record.snapshot_provenance_status,
          source_name: record.snapshot_source_name,
          source_url: record.snapshot_source_url,
          notes: record.notes
        }
      end

      def planned_workout(record)
        {
          id: record.id,
          person_id: record.person_id,
          workout_template: workout_template(record.workout_template),
          scheduled_on: record.scheduled_on.iso8601,
          performed_on: record.training_session&.performed_on&.iso8601,
          training_session_id: record.training_session_id,
          status: record.status.to_s,
          skipped_at: record.skipped_at&.utc&.iso8601,
          skip_reason: record.skip_reason
        }
      end

      def metric(metric, value_record = nil)
        value = value_record&.value
        value = value.utc.strftime("%H:%M:%S") if value.respond_to?(:strftime) && metric.time_of_day?
        {
          id: metric.id,
          key: metric.key,
          label: metric.label,
          value_type: metric.value_type,
          unit: metric.unit,
          value: value
        }
      end

      def person_habit(record)
        targets = record.person_habit_metrics.index_by(&:habit_metric_id)
        {
          id: record.id,
          person_id: record.person_id,
          habit_id: record.habit_id,
          name: record.habit.name,
          description: record.habit.description,
          active: record.active?,
          schedule: PersonHabit::WEEKDAYS.index_with { |day| record.public_send(day) },
          metrics: record.habit.habit_metrics.map { |metric| metric(metric, targets[metric.id]) }
        }
      end

      def habit_check_in(record)
        measurements = record.habit_check_in_measurements.index_by(&:habit_metric_id)
        {
          id: record.id,
          person_habit_id: record.person_habit_id,
          checked_on: record.checked_on.iso8601,
          notes: record.notes,
          measurements: record.person_habit.habit.habit_metrics.map do |metric|
            measurement = measurements[metric.id]
            metric(metric, measurement).merge(measurement_id: measurement&.id)
          end
        }
      end

      def activity_item(item)
        record = item.record
        {
          kind: item.kind.to_s,
          record_type: record.class.name,
          record_id: record.id,
          title: item.title,
          description: item.description,
          status: item.status.to_s
        }
      end
    end
  end
end
