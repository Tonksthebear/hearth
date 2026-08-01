module Agent::Mutation::ManagementOperations
  OPERATIONS = %w[
    create_person update_person create_recipe update_recipe create_exercise update_exercise
    create_workout_template update_workout_template create_habit update_habit
  ].freeze
  CREATE_OPERATIONS = {
    "person" => "create_person", "recipe" => "create_recipe", "exercise" => "create_exercise",
    "workout_template" => "create_workout_template", "habit" => "create_habit"
  }.freeze
  NESTED_KEYS = {
    "recipe" => %w[ingredients instructions], "workout_template" => %w[blocks], "habit" => %w[metrics]
  }.freeze
  SCALAR_KEYS = CREATE_OPERATIONS.to_h do |type, operation|
    properties = HearthMcp::ManagementTools::DEFINITIONS.fetch(operation).fetch(2)
    [ type, properties.keys.map(&:to_s) - %w[id] - NESTED_KEYS.fetch(type, []) ]
  end.freeze

  class << self
    def handles?(operation) = operation.to_s.in?(OPERATIONS)

    def validate_arguments!(operation:, arguments:)
      arguments = arguments.deep_stringify_keys
      if operation.include?("recipe") && arguments["ingredients"]
        keys = arguments["ingredients"].map { |row| row["key"] }
        raise ArgumentError, "Recipe ingredient keys must be unique" unless keys.compact.uniq.length == keys.length
      end
    end

    def record_for(operation:, arguments:, context:)
      id = arguments.deep_stringify_keys["id"]
      case operation
      when "update_person" then context.household.people.find(id)
      when "update_recipe" then context.household.recipes.find(id)
      when "update_exercise" then context.household.exercises.find(id)
      when "update_workout_template" then context.household.workout_templates.find(id)
      when "update_habit" then context.household.habits.find(id)
      end
    end

    def execute!(operation:, arguments:, context:)
      arguments = arguments.deep_stringify_keys
      case operation
      when "create_person"
        context.household.people.create!(arguments.slice("name"))
      when "update_person"
        record_for(operation:, arguments:, context:).tap { |record| record.update!(arguments.slice("name")) }
      when "create_recipe", "update_recipe"
        apply_recipe(operation, arguments, context)
      when "create_exercise", "update_exercise"
        apply_simple(operation, arguments, context, Exercise, SCALAR_KEYS.fetch("exercise"))
      when "create_workout_template", "update_workout_template"
        apply_workout(operation, arguments, context)
      when "create_habit", "update_habit"
        apply_habit(operation, arguments, context)
      end
    end

    def snapshot(record)
      case record
      when Person
        scalar_snapshot(record, "person")
      when Exercise
        scalar_snapshot(record, "exercise")
      when Recipe
        scalar_snapshot(record, "recipe").merge(
          "ingredients" => record.recipe_ingredients.map do |row|
            row.attributes.slice("id", "display_name", "display_quantity", "unit", "notes", "gram_weight", "position").merge("key" => row.form_key)
          end,
          "instructions" => record.recipe_instructions.map do |row|
            row.attributes.slice("id", "body", "duration_amount", "duration_unit", "temperature_amount", "temperature_unit", "position")
              .merge("ingredient_keys" => row.referenced_recipe_ingredients.map(&:form_key))
          end
        )
      when WorkoutTemplate
        scalar_snapshot(record, "workout_template").merge(
          "blocks" => record.workout_blocks.map do |block|
            block.attributes.slice("id", "title", "block_kind", "dose_class", "planned_duration_minutes", "notes", "position").merge(
              "prescriptions" => block.exercise_prescriptions.map do |row|
                row.attributes.slice(
                  "id", "exercise_id", "performance_kind", "sets_count", "rep_min", "rep_max", "work_seconds", "rest_seconds",
                  "target_distance_amount", "target_distance_unit", "target_count", "target_count_unit", "per_side", "tempo_cue",
                  "target_heart_rate_min", "target_heart_rate_max", "target_heart_rate_unit", "target_rpe", "target_rir",
                  "load_guidance", "notes", "dose_class", "position"
                )
              end
            )
          end
        )
      when Habit
        scalar_snapshot(record, "habit").merge(
          "metrics" => record.habit_metrics.map { |row| row.attributes.slice("id", "key", "label", "value_type", "unit", "position") }
        )
      else
        raise ArgumentError, "Unsupported management record"
      end
    end

    def preview(operation:, arguments:, context:)
      arguments = arguments.deep_stringify_keys
      record = record_for(operation:, arguments:, context:)
      before = record ? snapshot(record) : {}
      after = desired_projection(operation, arguments, before)
      type = aggregate_type(operation)
      children = child_diffs(before, after)
      scalar_changes = SCALAR_KEYS.fetch(type).filter_map do |key|
        next unless before[key] != after[key]
        { "field" => key, "before" => summarized(before[key]), "after" => summarized(after[key]) }
      end
      change_count = scalar_changes.length + children.values.sum { |diff| diff.values.sum(&:length) }
      {
        "version" => 1,
        "operation" => operation,
        "capability" => HearthMcp::ManagementTools.capability_for(operation),
        "aggregate" => { "type" => type, "id" => record&.id, "label" => after["name"] || after["title"] },
        "summary" => "#{operation.humanize}: #{change_count} reviewable change#{'s' unless change_count == 1}",
        "before_summary" => projection_summary(before),
        "after_summary" => projection_summary(after),
        "scalar_changes" => scalar_changes,
        "children" => children
      }
    end

    private
      def apply_simple(operation, arguments, context, klass, keys)
        record = operation.start_with?("create_") ? context.household.public_send(klass.model_name.collection).build : record_for(operation:, arguments:, context:)
        record.assign_attributes(arguments.slice(*keys))
        record.save!
        record
      end

      def apply_recipe(operation, arguments, context)
        record = operation == "create_recipe" ? context.household.recipes.build : record_for(operation:, arguments:, context:)
        record.assign_attributes(arguments.slice(*SCALAR_KEYS.fetch("recipe")))
        if arguments.key?("ingredients")
          record.recipe_ingredients_attributes = reconcile_rows(
            record.recipe_ingredients, arguments["ingredients"],
            %w[display_name display_quantity unit notes gram_weight form_key]
          ) do |row|
            row.transform_keys("name" => "display_name", "quantity" => "display_quantity", "key" => "form_key")
          end
        end
        if arguments.key?("instructions")
          record.recipe_instructions_attributes = reconcile_rows(
            record.recipe_instructions, arguments["instructions"],
            %w[body duration_amount duration_unit temperature_amount temperature_unit ingredient_reference_keys]
          ) { |row| row.transform_keys("ingredient_keys" => "ingredient_reference_keys") }
        end
        record.save!
        record
      end

      def apply_workout(operation, arguments, context)
        record = operation == "create_workout_template" ? context.household.workout_templates.build : record_for(operation:, arguments:, context:)
        record.assign_attributes(arguments.slice(*SCALAR_KEYS.fetch("workout_template")))
        if arguments.key?("blocks")
          record.workout_blocks_attributes = reconcile_rows(
            record.workout_blocks, arguments["blocks"], %w[title block_kind dose_class planned_duration_minutes notes exercise_prescriptions_attributes]
          ) do |block|
            prescriptions = block.delete("prescriptions")
            if prescriptions
              existing_block = block["id"] && record.workout_blocks.find(block["id"])
              association = existing_block ? existing_block.exercise_prescriptions : ExercisePrescription.none
              block["exercise_prescriptions_attributes"] = reconcile_rows(association, prescriptions, prescription_keys) do |row|
                row["exercise_id"] = context.household.exercises.find(row.fetch("exercise_id")).id
                row
              end
            end
            block
          end
        end
        record.save!
        record
      end

      def apply_habit(operation, arguments, context)
        record = operation == "create_habit" ? context.household.habits.build : record_for(operation:, arguments:, context:)
        record.assign_attributes(arguments.slice(*SCALAR_KEYS.fetch("habit")))
        if arguments.key?("metrics")
          record.habit_metrics_attributes = reconcile_rows(record.habit_metrics, arguments["metrics"], %w[key label value_type unit])
        end
        record.save!
        record
      end

      def reconcile_rows(association, submitted, allowed)
        existing = association.to_a.index_by { |row| row.id.to_s }
        seen = []
        rows = submitted.map.with_index(1) do |source, position|
          source = source.deep_stringify_keys
          source = yield(source) if block_given?
          id = source["id"]&.to_s
          raise ActiveRecord::RecordNotFound, "Nested record was not found" if id && !existing.key?(id)
          raise ArgumentError, "Nested record id is duplicated" if id && seen.include?(id)
          seen << id if id
          source.slice("id", *allowed).merge("position" => position)
        end
        rows.concat((existing.keys - seen).map { |id| { "id" => id, "_destroy" => true } })
      end

      def prescription_keys
        %w[exercise_id performance_kind sets_count rep_min rep_max work_seconds rest_seconds target_distance_amount
          target_distance_unit target_count target_count_unit per_side tempo_cue target_heart_rate_min target_heart_rate_max
          target_heart_rate_unit target_rpe target_rir load_guidance notes dose_class]
      end

      def scalar_snapshot(record, type)
        record.attributes.slice("id", *SCALAR_KEYS.fetch(type))
      end

      def aggregate_type(operation)
        operation.delete_prefix("create_").delete_prefix("update_")
      end

      def desired_projection(operation, arguments, before)
        type = aggregate_type(operation)
        after = before.deep_dup
        after = {} if operation.start_with?("create_")
        SCALAR_KEYS.fetch(type).each { |key| after[key] = arguments[key] if arguments.key?(key) }
        child_names(type).each do |name|
          next unless arguments.key?(name)
          before_by_id = Array(before[name]).index_by { |row| row["id"].to_s }
          after[name] = arguments[name].map.with_index(1) do |row, position|
            row = row.deep_stringify_keys
            prior = row["id"] ? before_by_id.fetch(row["id"].to_s, {}) : {}
            projected = prior.merge(row).merge("position" => position)
            if name == "blocks" && row.key?("prescriptions")
              prior_prescriptions = Array(prior["prescriptions"]).index_by { |item| item["id"].to_s }
              projected["prescriptions"] = row["prescriptions"].map.with_index(1) do |item, prescription_position|
                item = item.deep_stringify_keys
                prior_item = item["id"] ? prior_prescriptions.fetch(item["id"].to_s, {}) : {}
                prior_item.merge(item).merge("position" => prescription_position)
              end
            end
            projected
          end
        end
        project_recipe_reference_removals(after) if type == "recipe" && arguments.key?("ingredients") && !arguments.key?("instructions")
        after
      end

      def project_recipe_reference_removals(after)
        active_keys = Array(after["ingredients"]).map do |row|
          row["id"] ? "ingredient-#{row['id']}" : row["key"]
        end
        Array(after["instructions"]).each do |instruction|
          instruction["ingredient_keys"] = Array(instruction["ingredient_keys"]) & active_keys
        end
      end

      def child_names(type)
        NESTED_KEYS.fetch(type, [])
      end

      def child_diffs(before, after)
        diffs = (before.keys | after.keys).select { |key| before[key].is_a?(Array) || after[key].is_a?(Array) }.to_h do |key|
          [ key, diff_rows(Array(before[key]), Array(after[key])) ]
        end
        if before["blocks"].is_a?(Array) || after["blocks"].is_a?(Array)
          old_blocks = Array(before["blocks"]).index_by { |row| child_identity(row) }
          new_blocks = Array(after["blocks"]).index_by { |row| child_identity(row) }
          (old_blocks.keys | new_blocks.keys).each do |block_identity|
            old_rows = Array(old_blocks.dig(block_identity, "prescriptions"))
            new_rows = Array(new_blocks.dig(block_identity, "prescriptions"))
            next if old_rows.empty? && new_rows.empty?

            diffs["blocks.#{block_identity}.prescriptions"] = diff_rows(old_rows, new_rows)
          end
        end
        diffs
      end

      def diff_rows(old_rows, new_rows)
        old_by_key = old_rows.index_by { |row| child_identity(row) }
        new_by_key = new_rows.index_by { |row| child_identity(row) }
        shared = old_by_key.keys & new_by_key.keys
        {
          "added" => (new_by_key.keys - old_by_key.keys).map { |identity| compact_child(new_by_key.fetch(identity)) },
          "removed" => (old_by_key.keys - new_by_key.keys).map { |identity| compact_child(old_by_key.fetch(identity)) },
          "updated" => shared.filter_map do |identity|
            old_row, new_row = old_by_key.fetch(identity), new_by_key.fetch(identity)
            changes = (old_row.keys | new_row.keys).filter_map do |field|
              next if field.in?(%w[position prescriptions]) || old_row[field] == new_row[field]
              { "field" => field, "before" => summarized(old_row[field]), "after" => summarized(new_row[field]) }
            end
            { "identity" => identity, "changes" => changes } if changes.any?
          end,
          "reordered" => shared.filter_map do |identity|
            old_position, new_position = old_by_key[identity]["position"], new_by_key[identity]["position"]
            { "identity" => identity, "from" => old_position, "to" => new_position } if old_position != new_position
          end
        }
      end

      def child_identity(row) = (row["id"] || row["key"] || "position-#{row['position']}").to_s

      def compact_child(row)
        { "identity" => child_identity(row), "position" => row["position"], "label" => summarized(row["name"] || row["title"] || row["label"] || row["body"]) }
      end

      def projection_summary(value)
        return "None" if value.blank?
        label = value["name"] || value["title"] || value["id"]
        counts = value.filter_map { |key, rows| "#{rows.length} #{key}" if rows.is_a?(Array) }
        summarized([ label, *counts ].compact.join(" · "))
      end

      def summarized(value)
        return value unless value.is_a?(String)

        value.length > Agent::MutationProposal::PREVIEW_SUMMARY_MAX_LENGTH ? "#{value.first(197)}..." : value
      end
  end
end
