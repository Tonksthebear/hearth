module Agent::Mutation::Operations
  class Prohibited < StandardError; end

  MEAL_ITEM_KEYS = %w[
    id source_kind recipe_id ingredient_id snapshot_label portion_amount portion_unit
    substitutions notes _destroy recipe_feedback_attributes
  ].freeze
  TRAINING_SESSION_KEYS = %w[
    snapshot_title performed_on notes training_session_blocks_attributes
  ].freeze
  BLOCK_KEYS = %w[
    id snapshot_title snapshot_block_kind snapshot_dose_class actual_duration_seconds notes
    _destroy training_session_exercises_attributes
  ].freeze
  EXERCISE_KEYS = %w[
    id exercise_id snapshot_name snapshot_modality snapshot_movement_pattern snapshot_equipment
    snapshot_guidance snapshot_performance_kind snapshot_dose_class snapshot_rep_min snapshot_rep_max
    snapshot_work_seconds snapshot_rest_seconds snapshot_target_distance_amount snapshot_target_distance_unit
    snapshot_target_count snapshot_target_count_unit snapshot_per_side snapshot_tempo_cue
    snapshot_target_heart_rate_min snapshot_target_heart_rate_max snapshot_target_heart_rate_unit
    snapshot_target_rpe snapshot_target_rir snapshot_load_guidance difficulty soreness_or_pain
    substitution next_time_adjustment notes _destroy training_sets_attributes
  ].freeze
  SET_KEYS = %w[
    id dose_class reps load_amount load_unit duration_seconds rest_seconds distance_amount distance_unit
    count count_unit average_heart_rate_bpm peak_heart_rate_bpm rpe rir completed notes _destroy
  ].freeze

  class << self
    def execute!(operation:, arguments:, proposal:)
      context = proposal
      before = expected_state(operation: operation, arguments: arguments, proposal: proposal)
      record = dispatch(operation, arguments.deep_stringify_keys, context)
      after = operation.start_with?("delete_") ? {} : snapshot(record)
      { before: before, after: after, result: result_for(record) }
    end

    def expected_state(operation:, arguments:, proposal:)
      arguments = arguments.deep_stringify_keys
      record = record_for(operation, arguments, proposal)
      record ? snapshot(record) : {}
    end

    def preview(operation:, arguments:, context:)
      arguments = arguments.deep_stringify_keys
      record = record_for(operation, arguments, context)
      {
        "operation" => operation,
        "person" => { "id" => context.person.id, "name" => context.person.name },
        "effect" => preview_effect(operation, record, arguments),
        "before" => record ? snapshot(record) : {},
        "after" => arguments.except("id", "idempotency_key")
      }
    end

    def consequential?(operation:, arguments:, context:)
      return true if operation.start_with?("delete_", "unlog_", "unplan_")
      return true if operation.in?(%w[ update_weekly_dose_targets upsert_person_habit ])
      return true if operation == "update_training_session" && record_for(operation, arguments, context)&.completed?
      return true if operation == "update_meal" && destructive_feedback_change?(arguments, context)

      false
    end

    private
      def dispatch(operation, arguments, context)
        case operation
        when "create_planned_meal" then create_planned_meal(arguments, context)
        when "update_planned_meal" then update_planned_meal(arguments, context)
        when "delete_planned_meal" then delete_planned_meal(arguments, context)
        when "log_planned_meal" then log_planned_meal(arguments, context)
        when "create_meal" then create_meal(arguments, context)
        when "update_meal" then update_meal(arguments, context)
        when "delete_meal" then delete_meal(arguments, context)
        when "create_training_session" then create_training_session(arguments, context)
        when "update_training_session" then update_training_session(arguments, context)
        when "complete_training_session" then complete_training_session(arguments, context)
        when "delete_training_session" then delete_training_session(arguments, context)
        when "update_weekly_dose_targets" then update_weekly_dose_targets(arguments, context)
        when "upsert_person_habit" then upsert_person_habit(arguments, context)
        when "create_habit_check_in" then create_habit_check_in(arguments, context)
        when "update_habit_check_in" then update_habit_check_in(arguments, context)
        when "delete_habit_check_in" then delete_habit_check_in(arguments, context)
        else raise ArgumentError, "Unsupported mutation operation"
        end
      end

      def create_planned_meal(arguments, context)
        record = PlannedMeal.build_for(
          household: context.household,
          planned_on: date(arguments.fetch("planned_on")),
          recipe_id: arguments.fetch("recipe_id"),
          person_id: context.person.id
        )
        record.save!
        record
      end

      def update_planned_meal(arguments, context)
        record = context.person.planned_meals.find(arguments.fetch("id"))
        record.update!(
          planned_on: arguments.key?("planned_on") ? date(arguments["planned_on"]) : record.planned_on,
          recipe: arguments.key?("recipe_id") ? context.household.recipes.find(arguments["recipe_id"]) : record.recipe
        )
        record
      end

      def delete_planned_meal(arguments, context)
        record = context.person.planned_meals.find(arguments.fetch("id"))
        raise Prohibited, "A logged planned meal must be unlogged separately before it can be unplanned" if record.meals.exists?
        snapshot = snapshot(record)
        record.destroy!
        snapshot
      end

      def log_planned_meal(arguments, context)
        context.household.planned_meals.visible_to(context.person).find(arguments.fetch("id")).convert_for!(context.person)
      end

      def create_meal(arguments, context)
        record = Meal.build_for(household: context.household, person: context.person, attributes: meal_attributes(arguments, context))
        record.save!
        record
      end

      def update_meal(arguments, context)
        record = context.person.meals.find(arguments.fetch("id"))
        record.assign_attributes(meal_attributes(arguments.except("id"), context))
        record.save!
        record
      end

      def delete_meal(arguments, context)
        record = context.person.meals.includes(meal_items: :recipe_feedback).find(arguments.fetch("id"))
        prior = snapshot(record)
        record.destroy!
        prior
      end

      def create_training_session(arguments, context)
        record = context.person.training_sessions.build(training_attributes(arguments))
        record.household = context.household
        record.started_at ||= Time.current
        record.normalize_positions.save!
        record
      end

      def update_training_session(arguments, context)
        record = context.person.training_sessions.find(arguments.fetch("id"))
        record.assign_attributes(training_attributes(arguments.except("id")))
        record.normalize_positions.save!
        record
      end

      def complete_training_session(arguments, context)
        context.person.training_sessions.find(arguments.fetch("id")).tap(&:complete!)
      end

      def delete_training_session(arguments, context)
        record = context.person.training_sessions.find(arguments.fetch("id"))
        raise Prohibited, "Completed training sessions cannot be deleted" if record.completed?
        prior = snapshot(record)
        record.destroy!
        prior
      end

      def update_weekly_dose_targets(arguments, context)
        context.person.update!(arguments.slice(
          "weekly_strength_sessions_target", "weekly_structured_minutes_target",
          "weekly_zone2_minutes_target", "weekly_vigorous_minutes_target"
        ))
        context.person
      end

      def upsert_person_habit(arguments, context)
        habit = context.household.habits.find(arguments.fetch("habit_id"))
        record = context.person.person_habits.find_or_initialize_by(habit: habit)
        record.assign_attributes(arguments.slice("active", *PersonHabit::WEEKDAYS))
        if arguments["person_habit_metrics_attributes"]
          record.person_habit_metrics_attributes = arguments["person_habit_metrics_attributes"].map do |row|
            row.slice("id", "habit_metric_id", "number_value", "duration_value", "time_of_day_value", "boolean_value")
          end
        end
        record.ensure_target_rows.save!
        record
      end

      def create_habit_check_in(arguments, context)
        person_habit = context.person.person_habits.find(arguments.fetch("person_habit_id"))
        person_habit.habit_check_ins.create!(habit_check_in_attributes(arguments))
      end

      def update_habit_check_in(arguments, context)
        record = habit_check_ins(context).find(arguments.fetch("id"))
        record.update!(habit_check_in_attributes(arguments.except("id", "person_habit_id")))
        record
      end

      def delete_habit_check_in(arguments, context)
        record = habit_check_ins(context).find(arguments.fetch("id"))
        prior = snapshot(record)
        record.destroy!
        prior
      end

      def meal_attributes(arguments, context)
        attributes = arguments.slice("eaten_on", "eaten_at", "notes")
        attributes["eaten_on"] = date(attributes["eaten_on"]) if attributes["eaten_on"]
        attributes["meal_items_attributes"] = Array(arguments["meal_items"]).map.with_index(1) do |row, position|
          item = row.slice(*MEAL_ITEM_KEYS)
          item["position"] = position
          item["recipe"] = context.household.recipes.find(item.delete("recipe_id")) if item["recipe_id"]
          item["ingredient"] = context.household.ingredients.find(item.delete("ingredient_id")) if item["ingredient_id"]
          feedback = item["recipe_feedback_attributes"]
          item["recipe_feedback_attributes"] = feedback.slice("id", "body", "_destroy") if feedback
          item
        end if arguments.key?("meal_items")
        attributes
      end

      def training_attributes(arguments)
        arguments.slice(*TRAINING_SESSION_KEYS).tap do |attributes|
          attributes["performed_on"] = date(attributes["performed_on"]) if attributes["performed_on"]
          blocks = Array(attributes.delete("training_session_blocks_attributes") || arguments["blocks"])
          attributes["training_session_blocks_attributes"] = blocks.map.with_index(1) do |block, block_position|
            sanitized = block.slice(*BLOCK_KEYS).merge("position" => block_position)
            exercises = Array(sanitized.delete("training_session_exercises_attributes") || block["exercises"])
            sanitized["training_session_exercises_attributes"] = exercises.map.with_index(1) do |exercise, exercise_position|
              item = exercise.slice(*EXERCISE_KEYS).merge("position" => exercise_position)
              sets = Array(item.delete("training_sets_attributes") || exercise["sets"])
              item["training_sets_attributes"] = sets.map.with_index(1) { |set, position| set.slice(*SET_KEYS).merge("position" => position) }
              item
            end
            sanitized
          end if blocks.any?
        end
      end

      def habit_check_in_attributes(arguments)
        attributes = arguments.slice("checked_on", "notes")
        attributes["checked_on"] = date(attributes["checked_on"]) if attributes["checked_on"]
        if arguments["measurements"]
          attributes["habit_check_in_measurements_attributes"] = arguments["measurements"].map do |row|
            row.slice("id", "habit_metric_id", "number_value", "duration_value", "time_of_day_value", "boolean_value")
          end
        end
        attributes
      end

      def record_for(operation, arguments, context)
        id = arguments["id"]
        case operation
        when "update_planned_meal", "delete_planned_meal"
          context.person.planned_meals.find(id)
        when "log_planned_meal"
          context.household.planned_meals.visible_to(context.person).find(id)
        when "update_meal", "delete_meal" then context.person.meals.find(id)
        when "update_training_session", "complete_training_session", "delete_training_session"
          context.person.training_sessions.find(id)
        when "update_habit_check_in", "delete_habit_check_in" then habit_check_ins(context).find(id)
        when "update_weekly_dose_targets" then context.person
        when "upsert_person_habit" then context.person.person_habits.find_by(habit_id: arguments["habit_id"])
        end
      end

      def habit_check_ins(context)
        HabitCheckIn.joins(:person_habit).where(person_habits: { person_id: context.person.id })
      end

      def destructive_feedback_change?(arguments, context)
        return false unless arguments["id"] && arguments["meal_items"]
        existing = context.person.meals.includes(meal_items: :recipe_feedback).find(arguments["id"])
        arguments["meal_items"].any? do |item|
          feedback = item["recipe_feedback_attributes"] || {}
          prior = existing.meal_items.find { |candidate| candidate.id == item["id"].to_i }&.recipe_feedback
          prior && ActiveModel::Type::Boolean.new.cast(feedback["_destroy"])
        end
      end

      def preview_effect(operation, record, arguments)
        label = record.respond_to?(:description) ? record.description : record&.try(:snapshot_title)
        [ operation.humanize, label, arguments["planned_on"] || arguments["eaten_on"] ].compact.join(": ")
      end

      def snapshot(record)
        return record if record.is_a?(Hash)
        return {} unless record
        case record
        when Meal
          record.as_json.except("created_at", "updated_at").merge(
            "meal_items" => record.meal_items.map do |item|
              item.as_json.except("created_at", "updated_at").merge("recipe_feedback" => item.recipe_feedback&.as_json&.except("created_at", "updated_at"))
            end
          )
        when TrainingSession
          record.as_json.except("created_at", "updated_at").merge(
            "blocks" => record.training_session_blocks.map do |block|
              block.as_json.except("created_at", "updated_at").merge(
                "exercises" => block.training_session_exercises.map do |exercise|
                  exercise.as_json.except("created_at", "updated_at").merge(
                    "sets" => exercise.training_sets.map { |set| set.as_json.except("created_at", "updated_at") }
                  )
                end
              )
            end
          )
        when HabitCheckIn
          record.as_json.except("created_at", "updated_at").merge(
            "measurements" => record.habit_check_in_measurements.map { |row| row.as_json.except("created_at", "updated_at") }
          )
        else
          record.as_json.except("created_at", "updated_at")
        end
      end

      def result_for(record)
        record.is_a?(Hash) ? { "deleted" => true } : { "id" => record.id, "type" => record.class.name }
      end

      def date(value)
        Date.iso8601(value.to_s)
      rescue Date::Error, ArgumentError
        raise ArgumentError, "date must be ISO 8601"
      end
  end
end
