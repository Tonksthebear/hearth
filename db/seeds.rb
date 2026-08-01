# Demo data is opt-in so a normal production boot remains on the first-run setup path.
Nutrient.ensure_defaults!

if ENV["HEARTH_DEMO_DATA"] == "1"
  demo_email = "demo@hearth.local"
  demo_password = ENV["HEARTH_DEMO_PASSWORD"]

  raise "Set HEARTH_DEMO_PASSWORD before loading demo data." if demo_password.blank?

  household = Household.first

  if household && !household.users.exists?(email_address: demo_email)
    warn "Hearth demo data skipped: this installation already belongs to a non-demo household."
  else
    Household.transaction do
      unless household
        household = Household.bootstrap(
          household_attributes: { name: "Hearth Demo" },
          person_attributes: {
            name: "Alex",
            weekly_structured_minutes_target: 150,
            weekly_strength_sessions_target: 2,
            weekly_zone2_minutes_target: 90,
            weekly_vigorous_minutes_target: 20
          },
          user_attributes: {
            email_address: demo_email,
            password: demo_password,
            password_confirmation: demo_password
          }
        )
        raise ActiveRecord::RecordInvalid, household unless household.persisted?
      end

      alex = household.people.find_or_initialize_by(name: "Alex")
      alex.update!(
        weekly_structured_minutes_target: 150,
        weekly_strength_sessions_target: 2,
        weekly_zone2_minutes_target: 90,
        weekly_vigorous_minutes_target: 20
      )
      sam = household.people.find_or_create_by!(name: "Sam")

      oats = household.recipes.find_or_initialize_by(title: "Apple cinnamon oats")
      oats.assign_attributes(
        description: "A simple make-ahead breakfast with fruit and seeds.",
        yield: "2 servings",
        serving_count: 2,
        source_name: "Hearth demo kitchen",
        provenance_status: "observed"
      )
      oats.recipe_ingredients_attributes = [
        { position: 1, display_quantity: "1", unit: "cup", display_name: "rolled oats", form_key: "oats" },
        { position: 2, display_quantity: "2", unit: "cups", display_name: "water", form_key: "water" },
        { position: 3, display_quantity: "1", unit: nil, display_name: "apple", notes: "diced", form_key: "apple" },
        { position: 4, display_quantity: "1", unit: "tbsp", display_name: "chia seeds", form_key: "chia" }
      ] if oats.new_record?
      oats.recipe_instructions_attributes = [
        { position: 1, body: "Simmer the oats and water until tender.", duration_amount: 10, duration_unit: "minutes", ingredient_reference_keys: %w[oats water] },
        { position: 2, body: "Fold in the apple, cinnamon, and chia seeds.", ingredient_reference_keys: %w[apple chia] }
      ] if oats.new_record?
      oats.save!
      oats.recipe_ingredients.find_by!(display_name: "rolled oats").update!(gram_weight: 80)
      oats.recipe_ingredients.find_by!(display_name: "water").update!(gram_weight: 480)
      oats.recipe_ingredients.find_by!(display_name: "apple").update!(gram_weight: 180)
      oats.recipe_ingredients.find_by!(display_name: "chia seeds").update!(gram_weight: 12)

      oats_ingredient = household.ingredients.find_by!(normalized_name: "rolled oats")
      oats_ingredient.update!(nutrition_provenance_status: :observed, nutrition_source_name: "Hearth demo kitchen")
      {
        "energy" => 379, "protein" => 13.15, "carbohydrates" => 67.7,
        "fat" => 6.52, "fiber" => 10.1, "sodium" => 6
      }.each do |key, amount|
        oats_ingredient.ingredient_nutrient_values.find_or_initialize_by(nutrient: Nutrient.find_by!(key:)).update!(amount_per_100_grams: amount)
      end

      bowl = household.recipes.find_or_initialize_by(title: "Roasted vegetable grain bowl")
      bowl.assign_attributes(
        description: "A flexible grain bowl for a shared weeknight meal.",
        yield: "4 servings",
        serving_count: 4,
        source_name: "Hearth demo kitchen",
        provenance_status: "observed"
      )
      bowl.recipe_ingredients_attributes = [
        { position: 1, display_quantity: "2", unit: "cups", display_name: "cooked brown rice", form_key: "rice" },
        { position: 2, display_quantity: "4", unit: "cups", display_name: "mixed vegetables", form_key: "vegetables" },
        { position: 3, display_quantity: "1", unit: "can", display_name: "chickpeas", notes: "drained", form_key: "chickpeas" },
        { position: 4, display_quantity: "2", unit: "tbsp", display_name: "olive oil", form_key: "oil" }
      ] if bowl.new_record?
      bowl.recipe_instructions_attributes = [
        { position: 1, body: "Roast the vegetables and chickpeas until browned.", duration_amount: 25, duration_unit: "minutes", temperature_amount: 425, temperature_unit: "F", ingredient_reference_keys: %w[vegetables chickpeas] },
        { position: 2, body: "Serve over rice and finish with olive oil.", ingredient_reference_keys: %w[rice oil] }
      ] if bowl.new_record?
      bowl.save!

      week_start = Date.current.beginning_of_week
      household.planned_meals.find_or_initialize_by(person: nil, recipe: bowl).tap do |meal|
        meal.planned_on = week_start + 2.days
        meal.save!
      end
      household.planned_meals.find_or_initialize_by(person: alex, recipe: oats).tap do |meal|
        meal.planned_on = week_start + 1.day
        meal.save!
      end
      household.meals.find_or_initialize_by(person: alex, eaten_on: week_start).tap do |meal|
        meal.meal_items.build(source_kind: :recipe, recipe: oats, position: 1) if meal.new_record?
        meal.save!
      end
      household.meals.find_or_initialize_by(person: sam, eaten_on: week_start).tap do |meal|
        meal.meal_items.build(source_kind: :free_text, snapshot_label: "Vegetable soup and toast", position: 1) if meal.new_record?
        meal.save!
      end

      squat = household.exercises.find_or_create_by!(name: "Goblet squat") do |exercise|
        exercise.modality = "strength"
        exercise.movement_pattern = "squat"
        exercise.equipment = "Dumbbell or kettlebell"
        exercise.guidance = "Use a comfortable range of motion."
      end
      walk = household.exercises.find_or_create_by!(name: "Brisk walk") do |exercise|
        exercise.modality = "cardio"
        exercise.movement_pattern = "locomotion_cardio"
        exercise.equipment = "None"
        exercise.guidance = "Keep a conversational pace."
      end

      workout = household.workout_templates.find_or_initialize_by(title: "Balanced strength and walk")
      workout.assign_attributes(
        description: "A short strength block followed by conversational aerobic work.",
        provenance_status: "personal"
      )
      if workout.new_record?
        strength = workout.workout_blocks.build(
          position: 1,
          title: "Strength",
          block_kind: "strength",
          dose_class: "strength",
          planned_duration_minutes: 20
        )
        strength.exercise_prescriptions.build(
          exercise: squat,
          position: 1,
          performance_kind: "reps",
          dose_class: "strength",
          sets_count: 2,
          rep_min: 8,
          rep_max: 10,
          target_rpe: 7
        )
        zone2 = workout.workout_blocks.build(
          position: 2,
          title: "Zone 2",
          block_kind: "zone2",
          dose_class: "zone2",
          planned_duration_minutes: 30
        )
        zone2.exercise_prescriptions.build(
          exercise: walk,
          position: 1,
          performance_kind: "duration",
          dose_class: "zone2",
          sets_count: 1,
          work_seconds: 1_800
        )
      end
      workout.save!

      session = household.training_sessions.find_by(person: alex, workout_template: workout)
      session ||= TrainingSession.start_from(template: workout, person: alex, performed_on: week_start)
      session.update!(
        performed_on: week_start,
        started_at: Time.zone.local(week_start.year, week_start.month, week_start.day, 7)
      )
      session.training_session_blocks.each do |block|
        block.training_session_exercises.each do |session_exercise|
          session_exercise.training_sets.each do |set|
            if session_exercise.snapshot_performance_kind_duration?
              set.update!(completed: true, duration_seconds: 1_800)
            else
              set.update!(completed: true, reps: 8, load_amount: 20, load_unit: "kg", rpe: 7)
            end
          end
        end
      end
      session.complete! unless session.completed?

      hydration = household.habits.find_or_initialize_by(name: "Water")
      hydration.description = "Record whether the day's hydration target was met."
      hydration.habit_metrics_attributes = [
        { position: 1, key: "completed", label: "Completed", value_type: "boolean" }
      ] if hydration.new_record?
      hydration.save!

      movement = household.habits.find_or_initialize_by(name: "Post-meal movement")
      movement.description = "Record intentional movement after a meal."
      movement.habit_metrics_attributes = [
        { position: 1, key: "duration", label: "Duration", value_type: "duration", unit: "minutes" }
      ] if movement.new_record?
      movement.save!

      alex_water = alex.person_habits.find_or_create_by!(habit: hydration)
      alex_water.ensure_target_rows
      alex_water.person_habit_metrics.find { |target| target.habit_metric.key == "completed" }.boolean_value = true
      alex_water.save!

      alex_movement = alex.person_habits.find_or_create_by!(habit: movement)
      alex_movement.ensure_target_rows
      alex_movement.person_habit_metrics.find { |target| target.habit_metric.key == "duration" }.duration_value = 10
      alex_movement.save!

      sam_movement = sam.person_habits.find_or_create_by!(habit: movement)
      sam_movement.ensure_target_rows
      sam_movement.person_habit_metrics.find { |target| target.habit_metric.key == "duration" }.duration_value = 10
      sam_movement.save!

      [
        [ alex_water, { "completed" => { boolean_value: true } } ],
        [ alex_movement, { "duration" => { duration_value: 12 } } ]
      ].each do |person_habit, values|
        check_in = person_habit.habit_check_ins.find_or_initialize_by(checked_on: week_start)
        check_in.ensure_measurement_rows
        check_in.habit_check_in_measurements.each do |measurement|
          measurement.assign_attributes(values.fetch(measurement.habit_metric.key))
        end
        check_in.save!
      end
    end

    puts "Hearth demo data ready: sign in as #{demo_email}."
  end
end
