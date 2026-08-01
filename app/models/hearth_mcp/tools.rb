require "mcp"

module HearthMcp
  module Tools
    CAPABILITY = "health.read"
    class Base < MCP::Tool
      RECORD_SCHEMA = { type: "object" }.freeze
      RECORDS_SCHEMA = { type: "array", items: RECORD_SCHEMA }.freeze
      STRING_SCHEMA = { type: "string" }.freeze
      PAGE_SCHEMA = {
        type: "object",
        properties: {
          items: RECORDS_SCHEMA,
          next_cursor: { type: [ "string", "null" ] }
        },
        required: %w[items next_cursor],
        additionalProperties: false
      }.freeze
      DATA_PROPERTIES = {
        "get_current_context" => {
          household: RECORD_SCHEMA,
          person: RECORD_SCHEMA,
          conversation_id: { type: "integer" },
          agent_session_id: { type: "integer" },
          capabilities: { type: "array", items: STRING_SCHEMA }
        },
        "get_today" => { date: STRING_SCHEMA, sections: RECORDS_SCHEMA },
        "get_household_week" => { start_date: STRING_SCHEMA, end_date: STRING_SCHEMA, planned_meals: RECORDS_SCHEMA, people: RECORDS_SCHEMA },
        "get_recipe" => {
          id: { type: "integer" },
          title: STRING_SCHEMA,
          description: { type: [ "string", "null" ] },
          yield: { type: [ "string", "null" ] },
          provenance_status: STRING_SCHEMA,
          source_name: { type: [ "string", "null" ] },
          source_url: { type: [ "string", "null" ] },
          ingredients: RECORDS_SCHEMA
        },
        "get_meal_week" => { start_date: STRING_SCHEMA, end_date: STRING_SCHEMA, planned_meals: RECORDS_SCHEMA, meals: RECORDS_SCHEMA },
        "get_shopping_list" => { start_date: STRING_SCHEMA, end_date: STRING_SCHEMA, entries: RECORDS_SCHEMA },
        "get_activity_week" => { start_date: STRING_SCHEMA, end_date: STRING_SCHEMA, days: RECORDS_SCHEMA },
        "get_training_week" => {
          start_date: STRING_SCHEMA,
          end_date: STRING_SCHEMA,
          completed_sessions: RECORDS_SCHEMA,
          in_progress_sessions: RECORDS_SCHEMA,
          metrics: RECORDS_SCHEMA
        },
        "get_weekly_dose_targets" => { person_id: { type: "integer" }, start_date: STRING_SCHEMA, targets: RECORDS_SCHEMA },
        "get_recovery_day" => { date: STRING_SCHEMA, dates: { type: "array", items: STRING_SCHEMA }, entries: RECORDS_SCHEMA }
      }.freeze
      PAGED_TOOLS = %w[
        list_people list_recipes list_planned_meals list_meals list_planned_workouts
        list_exercises list_workout_templates list_training_sessions list_habits
        list_person_habits list_habit_check_ins
      ].freeze
      ENVELOPE_SCHEMA = {
        type: "object",
        properties: {
          origin: { type: "string", const: "hearth_database" },
          timezone: { type: "string", const: "UTC" },
          generated_at: { type: "string", format: "date-time" },
          data: RECORD_SCHEMA
        },
        required: %w[origin timezone generated_at data],
        additionalProperties: false
      }.freeze

      class << self
        def contract(name:, description:, properties: {}, required: [])
          tool_name name
          self.description description
          input_schema(
            type: "object",
            properties: properties,
            required: required,
            additionalProperties: false
          )
          output_schema envelope_schema(name)
          annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true, open_world_hint: false)
        end

        def response(data, server_context:)
          envelope = Serializer.envelope(data)
          json = JSON.generate(envelope)
          tokens = (json.bytesize / 4.0).ceil
          grant = server_context.fetch(:grant)
          return error("Grant call limit exhausted") unless grant.consume(calls: 1) == 1
          unless grant.consume(calls: 0, output_tokens: tokens) == 1
            return error("Response exceeds the remaining output budget")
          end

          MCP::Tool::Response.new(
            [ { type: "text", text: json } ],
            structured_content: envelope
          )
        end

        def error(message, server_context: nil)
          if server_context && grant(server_context).consume(calls: 1) != 1
            message = "Grant call limit exhausted"
          end
          MCP::Tool::Response.new([ { type: "text", text: JSON.generate(error: message) } ], error: true)
        end

        def grant(server_context) = server_context.fetch(:grant)
        def household(server_context) = grant(server_context).household
        def person(server_context) = grant(server_context).person

        def date(value)
          Date.iso8601(value.to_s)
        rescue Date::Error, ArgumentError
          raise ArgumentError, "date must be ISO 8601"
        end

        def week_date(value) = value.present? ? date(value) : Date.current

        def page(scope, limit:, cursor:, &serializer)
          result = Page.new(scope, limit: limit, cursor: cursor)
          { items: result.records.map(&serializer), next_cursor: result.next_cursor }
        end

        def paginated_response(scope, limit:, cursor:, server_context:, &serializer)
          response(page(scope, limit: limit, cursor: cursor, &serializer), server_context: server_context)
        rescue ArgumentError => exception
          error(exception.message, server_context: server_context)
        end

        private

        def envelope_schema(name)
          data_schema = if PAGED_TOOLS.include?(name)
            PAGE_SCHEMA
          else
            properties = DATA_PROPERTIES.fetch(name)
            {
              type: "object",
              properties: properties,
              required: properties.keys.map(&:to_s),
              additionalProperties: false
            }
          end
          ENVELOPE_SCHEMA.deep_dup.tap { |schema| schema[:properties][:data] = data_schema }
        end
      end
    end

    PAGE_PROPERTIES = {
      limit: { type: "integer", minimum: 1, maximum: Page::MAX_LIMIT, default: Page::DEFAULT_LIMIT },
      cursor: { type: "string", maxLength: 256 }
    }.freeze
    WEEK_PROPERTIES = { date: { type: "string", format: "date" } }.freeze

    class GetCurrentContext < Base
      contract name: "get_current_context", description: "Return the authorized Hearth household, person, conversation, and ACP session context."
      def self.call(server_context:)
        g = grant(server_context)
        response(
          {
            household: { id: g.household_id, name: g.household.name },
            person: Serializer.person(g.person),
            conversation_id: g.conversation_id,
            agent_session_id: g.agent_session_id,
            capabilities: g.capability_groups
          },
          server_context: server_context
        )
      end
    end

    class ListPeople < Base
      contract name: "list_people", description: "List people visible in the authorized household.", properties: PAGE_PROPERTIES
      def self.call(limit: Page::DEFAULT_LIMIT, cursor: nil, server_context:)
        paginated_response(household(server_context).people, limit: limit, cursor: cursor,
          server_context: server_context, &Serializer.method(:person))
      end
    end

    class GetToday < Base
      contract name: "get_today", description: "Return the selected person's daily execution view from Person::Today.", properties: { date: { type: "string", format: "date" } }
      def self.call(date: nil, server_context:)
        target = date ? self.date(date) : Date.current
        today = Person::Today.new(household: household(server_context), person: person(server_context), date: target)
        sections = today.sections.map do |section|
          {
            key: section.key.to_s,
            title: section.title,
            description: section.description,
            items: section.items.map { |item| Serializer.activity_item(item) }
          }
        end
        response({ date: target.iso8601, sections: sections }, server_context: server_context)
      end
    end

    class GetHouseholdWeek < Base
      contract name: "get_household_week", description: "Return the household-wide Monday-to-Sunday operational summary.", properties: WEEK_PROPERTIES
      def self.call(date: nil, server_context:)
        week = HouseholdWeek.new(household: household(server_context), person: person(server_context), date: week_date(date))
        people = week.person_summaries.map do |summary|
          {
            person: Serializer.person(summary.person),
            meals: summary.meals.map { |row| Serializer.meal(row) },
            training_sessions: summary.training_sessions.map { |row| Serializer.training_session(row) },
            habits: summary.habits.map do |habit|
              {
                person_habit_id: habit.entry.person_habit.id,
                name: habit.habit.name,
                days: habit.days.map { |day| { date: day.date.iso8601, status: day.status.to_s } }
              }
            end
          }
        end
        response(
          {
            start_date: week.start_date.iso8601,
            end_date: week.end_date.iso8601,
            planned_meals: week.planned_meals.map { |row| Serializer.planned_meal(row) },
            people: people
          },
          server_context: server_context
        )
      end
    end

    class ListRecipes < Base
      contract name: "list_recipes", description: "List the authorized household recipe catalog with provenance.", properties: PAGE_PROPERTIES
      def self.call(limit: Page::DEFAULT_LIMIT, cursor: nil, server_context:)
        paginated_response(household(server_context).recipes, limit: limit, cursor: cursor,
          server_context: server_context) { |row| Serializer.recipe(row) }
      end
    end

    class GetRecipe < Base
      contract name: "get_recipe",
        description: "Return one authorized household recipe, ingredients, attribution, and provenance status.",
        properties: { id: { type: "integer", minimum: 1 } },
        required: %w[id]
      def self.call(id:, server_context:)
        record = household(server_context).recipes.includes(recipe_ingredients: :ingredient).find_by(id: id)
        if record
          response(Serializer.recipe(record, detail: true), server_context: server_context)
        else
          error("Recipe not found", server_context: server_context)
        end
      end
    end

    class GetMealWeek < Base
      contract name: "get_meal_week", description: "Return the selected person's visible meal plans and logs for a Monday-to-Sunday week.", properties: WEEK_PROPERTIES
      def self.call(date: nil, server_context:)
        week = MealWeek.new(household: household(server_context), person: person(server_context), date: week_date(date))
        response(
          {
            start_date: week.start_date.iso8601,
            end_date: week.end_date.iso8601,
            planned_meals: week.planned_meals.map { |row| Serializer.planned_meal(row) },
            meals: week.meals.map { |row| Serializer.meal(row) }
          },
          server_context: server_context
        )
      end
    end

    class ListPlannedMeals < Base
      contract name: "list_planned_meals", description: "List meal plans visible to the selected person.", properties: PAGE_PROPERTIES
      def self.call(limit: Page::DEFAULT_LIMIT, cursor: nil, server_context:)
        scope = household(server_context).planned_meals.visible_to(person(server_context)).includes(:person, :recipe)
        paginated_response(scope, limit: limit, cursor: cursor, server_context: server_context) do |row|
          Serializer.planned_meal(row)
        end
      end
    end

    class ListMeals < Base
      contract name: "list_meals", description: "List complete observed meal events for the selected person.", properties: PAGE_PROPERTIES
      def self.call(limit: Page::DEFAULT_LIMIT, cursor: nil, server_context:)
        scope = person(server_context).meals.includes(meal_items: [ :recipe, :ingredient, :recipe_feedback ])
        paginated_response(scope, limit: limit, cursor: cursor,
          server_context: server_context) { |row| Serializer.meal(row) }
      end
    end

    class GetShoppingList < Base
      contract name: "get_shopping_list",
        description: "Return the persisted household shopping checklist without reconciling or creating it.",
        properties: WEEK_PROPERTIES
      def self.call(date: nil, server_context:)
        start_date = week_date(date).beginning_of_week(:monday)
        list = ShoppingList.existing_for(household: household(server_context), date: start_date)
        entries = list ? list.display_items.map { |item| shopping_entry(item) } : []
        response(
          { start_date: start_date.iso8601, end_date: (start_date + 6.days).iso8601, entries: entries },
          server_context: server_context
        )
      end

      def self.shopping_entry(item)
        {
          id: item.id,
          ingredient_id: item.ingredient_id,
          name: item.name,
          amount: item.quantity,
          unit: item.unit,
          notes: item.notes,
          completed: item.completed?,
          completed_at: item.completed_at&.utc&.iso8601,
          user_managed: item.user_managed?,
          sources: item.shopping_list_item_sources.map do |source|
            {
              planned_meal_id: source.planned_meal_id,
              planned_on: source.planned_meal.planned_on.iso8601,
              recipe_id: source.planned_meal.recipe_id,
              recipe_title: source.planned_meal.recipe.title,
              recipe_ingredient_id: source.recipe_ingredient_id
            }
          end
        }
      end
    end

    class GetActivityWeek < Base
      contract name: "get_activity_week",
        description: "Return the selected person's truthful weekly activity agenda, including scheduled intent and actual execution once.",
        properties: WEEK_PROPERTIES
      def self.call(date: nil, server_context:)
        week = ActivityWeek.new(household: household(server_context), person: person(server_context), date: week_date(date))
        days = week.days.map do |day|
          {
            date: day.date.iso8601,
            sections: day.sections.map do |section|
              { key: section.key.to_s, items: section.items.map { |item| Serializer.activity_item(item) } }
            end
          }
        end
        response(
          { start_date: week.start_date.iso8601, end_date: week.end_date.iso8601, days: days },
          server_context: server_context
        )
      end
    end

    class ListPlannedWorkouts < Base
      contract name: "list_planned_workouts", description: "List planned workout intent and linked execution without duplicating sessions.", properties: PAGE_PROPERTIES
      def self.call(limit: Page::DEFAULT_LIMIT, cursor: nil, server_context:)
        scope = person(server_context).planned_workouts.includes(:workout_template, :training_session)
        paginated_response(scope, limit: limit, cursor: cursor, server_context: server_context) do |row|
          Serializer.planned_workout(row)
        end
      end
    end

    class ListExercises < Base
      contract name: "list_exercises", description: "List exercises in the authorized household library.", properties: PAGE_PROPERTIES
      def self.call(limit: Page::DEFAULT_LIMIT, cursor: nil, server_context:)
        paginated_response(household(server_context).exercises, limit: limit, cursor: cursor,
          server_context: server_context, &Serializer.method(:exercise))
      end
    end

    class ListWorkoutTemplates < Base
      contract name: "list_workout_templates", description: "List workout templates with source and provenance.", properties: PAGE_PROPERTIES
      def self.call(limit: Page::DEFAULT_LIMIT, cursor: nil, server_context:)
        paginated_response(household(server_context).workout_templates, limit: limit, cursor: cursor,
          server_context: server_context, &Serializer.method(:workout_template))
      end
    end

    class ListTrainingSessions < Base
      contract name: "list_training_sessions", description: "List actual training executions for the selected person.", properties: PAGE_PROPERTIES
      def self.call(limit: Page::DEFAULT_LIMIT, cursor: nil, server_context:)
        paginated_response(person(server_context).training_sessions, limit: limit, cursor: cursor,
          server_context: server_context, &Serializer.method(:training_session))
      end
    end

    class GetTrainingWeek < Base
      contract name: "get_training_week", description: "Return selected-person training executions and dose progress for one week.", properties: WEEK_PROPERTIES
      def self.call(date: nil, server_context:)
        week = TrainingWeek.new(household: household(server_context), person: person(server_context), date: week_date(date))
        response(
          {
            start_date: week.start_date.iso8601,
            end_date: week.end_date.iso8601,
            completed_sessions: week.completed_sessions.map { |row| Serializer.training_session(row) },
            in_progress_sessions: week.in_progress_sessions.map { |row| Serializer.training_session(row) },
            metrics: week.metrics.map(&:to_h)
          },
          server_context: server_context
        )
      end
    end

    class GetWeeklyDoseTargets < Base
      contract name: "get_weekly_dose_targets", description: "Return configured weekly training targets with explicit units.", properties: WEEK_PROPERTIES
      def self.call(date: nil, server_context:)
        week = TrainingWeek.new(household: household(server_context), person: person(server_context), date: week_date(date))
        targets = week.metrics.map { |metric| metric.to_h.slice(:key, :label, :target, :unit) }
        response(
          { person_id: person(server_context).id, start_date: week.start_date.iso8601, targets: targets },
          server_context: server_context
        )
      end
    end

    class ListHabits < Base
      contract name: "list_habits", description: "List household habit definitions and typed metric schemas.", properties: PAGE_PROPERTIES
      def self.call(limit: Page::DEFAULT_LIMIT, cursor: nil, server_context:)
        paginated_response(household(server_context).habits.includes(:habit_metrics), limit: limit, cursor: cursor,
          server_context: server_context) do |habit|
          {
            id: habit.id,
            name: habit.name,
            description: habit.description,
            metrics: habit.habit_metrics.map { |metric| Serializer.metric(metric) }
          }
        end
      end
    end

    class ListPersonHabits < Base
      contract name: "list_person_habits", description: "List the selected person's habit schedules and typed targets.", properties: PAGE_PROPERTIES
      def self.call(limit: Page::DEFAULT_LIMIT, cursor: nil, server_context:)
        scope = person(server_context).person_habits.includes(habit: :habit_metrics, person_habit_metrics: :habit_metric)
        paginated_response(scope, limit: limit, cursor: cursor,
          server_context: server_context, &Serializer.method(:person_habit))
      end
    end

    class ListHabitCheckIns < Base
      contract name: "list_habit_check_ins",
        description: "List selected-person check-ins with boolean, number, duration, or time-of-day measurements and conditional units.",
        properties: PAGE_PROPERTIES
      def self.call(limit: Page::DEFAULT_LIMIT, cursor: nil, server_context:)
        ids = person(server_context).person_habit_ids
        scope = HabitCheckIn.where(person_habit_id: ids).includes(person_habit: { habit: :habit_metrics }, habit_check_in_measurements: :habit_metric)
        paginated_response(scope, limit: limit, cursor: cursor,
          server_context: server_context, &Serializer.method(:habit_check_in))
      end
    end

    class GetRecoveryDay < Base
      contract name: "get_recovery_day", description: "Return the selected person's seven-day habit/recovery projection.", properties: { date: { type: "string", format: "date" } }
      def self.call(date: nil, server_context:)
        target = date ? self.date(date) : Date.current
        day = RecoveryDay.new(household: household(server_context), person: person(server_context), date: target)
        entries = day.entries.map do |entry|
          statuses = day.dates.map do |item_date|
            check_in = entry.check_in_on(item_date)
            {
              date: item_date.iso8601,
              status: entry.status_on(item_date).to_s,
              check_in: check_in && Serializer.habit_check_in(check_in)
            }
          end
          { person_habit: Serializer.person_habit(entry.person_habit), statuses: statuses }
        end
        response(
          { date: target.iso8601, dates: day.dates.map(&:iso8601), entries: entries },
          server_context: server_context
        )
      end
    end

    ALL = [
      GetCurrentContext, ListPeople, GetToday, GetHouseholdWeek,
      ListRecipes, GetRecipe, GetMealWeek, ListPlannedMeals, ListMeals, GetShoppingList,
      GetActivityWeek, ListPlannedWorkouts, ListExercises, ListWorkoutTemplates,
      ListTrainingSessions, GetTrainingWeek, GetWeeklyDoseTargets,
      ListHabits, ListPersonHabits, ListHabitCheckIns, GetRecoveryDay
    ].freeze
  end
end
