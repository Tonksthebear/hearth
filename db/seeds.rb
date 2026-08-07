# Demo data is opt-in so a normal production boot remains on the first-run setup path.
Nutrient.ensure_defaults!

if ENV["HEARTH_DEMO_DATA"] == "1"
  demo_email = "demo@example.com"
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

      attach_demo_cover = lambda do |recipe, filename|
        next if recipe.cover.attached?

        path = Rails.root.join("db/seed_assets", filename)
        recipe.cover.attach(
          io: StringIO.new(path.binread),
          filename: filename,
          content_type: "image/jpeg"
        )
      end

      set_nutrition_profile = lambda do |ingredient, amounts|
        ingredient.update!(nutrition_provenance_status: :personal, nutrition_source_name: nil)
        amounts.each do |key, amount|
          ingredient.ingredient_nutrient_values
            .find_or_initialize_by(nutrient: Nutrient.find_by!(key:))
            .update!(amount_per_100_grams: amount)
        end
      end

      refresh_demo_portion = lambda do |item, amount, unit|
        item.update!(portion_amount: nil, portion_unit: nil)
        item.update!(portion_amount: amount, portion_unit: unit)
      end

      oats = household.recipes.find_or_initialize_by(title: "Apple cinnamon oats")
      oats.assign_attributes(
        description: "A simple make-ahead breakfast with fruit and seeds.",
        yield: "2 servings",
        serving_count: 2,
        source_name: nil,
        provenance_status: "personal"
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
      attach_demo_cover.call(oats, "apple-cinnamon-oats.jpg")

      {
        "rolled oats" => {
          "energy" => 379, "protein" => 13.15, "carbohydrates" => 67.7,
          "fat" => 6.52, "fiber" => 10.1, "sodium" => 6
        },
        "water" => {
          "energy" => 0, "protein" => 0, "carbohydrates" => 0,
          "fat" => 0, "fiber" => 0, "sodium" => 0
        },
        "apple" => {
          "energy" => 52, "protein" => 0.26, "carbohydrates" => 13.81,
          "fat" => 0.17, "fiber" => 2.4, "sodium" => 1
        },
        "chia seeds" => {
          "energy" => 486, "protein" => 16.54, "carbohydrates" => 42.12,
          "fat" => 30.74, "fiber" => 34.4, "sodium" => 16
        }
      }.each do |normalized_name, amounts|
        set_nutrition_profile.call(household.ingredients.find_by!(normalized_name:), amounts)
      end

      bowl = household.recipes.find_or_initialize_by(title: "Roasted vegetable grain bowl")
      bowl.assign_attributes(
        description: "A flexible grain bowl for a shared weeknight meal.",
        yield: "4 servings",
        serving_count: 4,
        source_name: "Hearth demo catalog",
        provenance_status: "adapted"
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
      bowl.recipe_ingredients.find_by!(display_name: "cooked brown rice").update!(gram_weight: 390)
      bowl.recipe_ingredients.find_by!(display_name: "mixed vegetables").update!(gram_weight: 600)
      bowl.recipe_ingredients.find_by!(display_name: "chickpeas").update!(gram_weight: 240)
      bowl.recipe_ingredients.find_by!(display_name: "olive oil").update!(gram_weight: 27)
      attach_demo_cover.call(bowl, "roasted-vegetable-grain-bowl.jpg")

      week_start = Date.current.beginning_of_week
      today = Date.current
      past_plan_date = today > week_start ? week_start : today
      past_bowl_plan = household.planned_meals.find_or_initialize_by(
        person: nil,
        recipe: bowl,
        planned_on: past_plan_date
      )
      past_bowl_plan.save!
      household.planned_meals.find_or_initialize_by(
        person: (alex if today == week_start),
        recipe: bowl,
        planned_on: today
      ).save!
      household.planned_meals.find_or_initialize_by(person: alex, recipe: oats, planned_on: week_start + 1.day).save!

      alex_meal = household.meals.find_or_initialize_by(person: alex, eaten_on: today)
      alex_meal.assign_attributes(
        eaten_at: Time.zone.local(today.year, today.month, today.day, 8, 15),
        notes: "Breakfast after the morning routine."
      )
      [
        {
          position: 1, source_kind: :recipe, recipe: oats, ingredient: nil,
          snapshot_label: oats.title, portion_amount: 1, portion_unit: "serving",
          substitutions: "Used oat milk for part of the water.", notes: "Good texture after resting overnight."
        },
        {
          position: 2, source_kind: :ingredient, recipe: nil,
          ingredient: household.ingredients.find_by!(normalized_name: "apple"),
          snapshot_label: "apple", portion_amount: 100, portion_unit: "g",
          substitutions: nil, notes: "Extra sliced apple."
        },
        {
          position: 3, source_kind: :free_text, recipe: nil, ingredient: nil,
          snapshot_label: "Coffee with a splash of milk", portion_amount: nil, portion_unit: nil,
          substitutions: nil, notes: "Free-text item keeps the nutrition summary visibly incomplete."
        }
      ].each do |attributes|
        item = alex_meal.meal_items.find_or_initialize_by(position: attributes.fetch(:position))
        item.assign_attributes(attributes)
      end
      alex_meal.save!
      refresh_demo_portion.call(alex_meal.meal_items.find_by!(position: 1), 1, "serving")
      refresh_demo_portion.call(alex_meal.meal_items.find_by!(position: 2), 100, "g")
      alex_meal.meal_items.find_by!(position: 1).tap do |item|
        item.create_recipe_feedback!(body: "Keep the apple pieces smaller next time; the cinnamon level was right.") unless item.recipe_feedback
      end

      sam_meal = household.meals.find_or_initialize_by(person: sam, eaten_on: week_start + 2.days)
      sam_meal.assign_attributes(
        planned_meal: past_bowl_plan,
        eaten_at: Time.zone.local((week_start + 2.days).year, (week_start + 2.days).month, (week_start + 2.days).day, 18, 30),
        notes: "Shared dinner logged from the household plan."
      )
      sam_item = sam_meal.meal_items.find_or_initialize_by(position: 1)
      sam_item.assign_attributes(
        source_kind: :recipe,
        recipe: bowl,
        ingredient: nil,
        snapshot_label: bowl.title,
        portion_amount: 1,
        portion_unit: "serving",
        substitutions: "Used broccoli and peppers for the mixed vegetables.",
        notes: "Packed the remaining serving for lunch."
      )
      sam_meal.save!
      refresh_demo_portion.call(sam_item, 1, "serving")
      sam_item.create_recipe_feedback!(body: "Add a little more acid at the table next time.") unless sam_item.recipe_feedback

      shopping_list = ShoppingList.for(household:, date: today)
      manual_item = shopping_list.items.find_or_initialize_by(generated_key: nil, name: "Dish soap")
      manual_item.assign_attributes(quantity: "1", notes: "Unscented refill")
      manual_item.save!
      shopping_list.items.find_by!(ingredient: household.ingredients.find_by!(normalized_name: "olive oil")).complete!
      shopping_list.items.find_by!(ingredient: household.ingredients.find_by!(normalized_name: "mixed vegetables")).tap do |item|
        item.apply_user_attributes(
          name: "Vegetables for grain bowls",
          notes: "Broccoli, peppers, and zucchini"
        ) unless item.user_managed?
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
      stairs = household.exercises.find_or_create_by!(name: "Stair climb") do |exercise|
        exercise.modality = "cardio"
        exercise.movement_pattern = "locomotion_cardio"
        exercise.equipment = "Stairs"
        exercise.guidance = "Use a steady pace and a handrail when needed."
      end
      carry = household.exercises.find_or_create_by!(name: "Suitcase carry") do |exercise|
        exercise.modality = "strength"
        exercise.movement_pattern = "carry"
        exercise.equipment = "Dumbbell or kettlebell"
        exercise.guidance = "Stay tall and use a clear, level walking path."
      end
      bike = household.exercises.find_or_create_by!(name: "Stationary bike") do |exercise|
        exercise.modality = "cardio"
        exercise.movement_pattern = "locomotion_cardio"
        exercise.equipment = "Stationary bike"
        exercise.guidance = "Choose a resistance that keeps every interval controlled."
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
          target_rpe: 7,
          target_rir: 2,
          tempo_cue: "3 seconds down, brief pause",
          load_guidance: "Use a load that leaves two good repetitions in reserve."
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

      conditioning = household.workout_templates.find_or_initialize_by(title: "Stairs, carries, and intervals")
      conditioning.assign_attributes(
        description: "A flexible session showing count, distance, per-side, interval, heart-rate, and feedback fields.",
        provenance_status: "personal"
      )
      if conditioning.new_record?
        practical = conditioning.workout_blocks.build(
          position: 1,
          title: "Practical conditioning",
          block_kind: "strength",
          dose_class: "strength",
          planned_duration_minutes: 15
        )
        practical.exercise_prescriptions.build(
          exercise: stairs,
          position: 1,
          performance_kind: "count",
          dose_class: "vigorous",
          sets_count: 3,
          target_count: 5,
          target_count_unit: "flights",
          rest_seconds: 60,
          target_rpe: 7
        )
        practical.exercise_prescriptions.build(
          exercise: carry,
          position: 2,
          performance_kind: "distance",
          dose_class: "strength",
          sets_count: 2,
          target_distance_amount: 30,
          target_distance_unit: "m",
          per_side: true,
          rest_seconds: 45,
          target_rpe: 7,
          load_guidance: "Switch hands after each 30 m row."
        )
        intervals = conditioning.workout_blocks.build(
          position: 2,
          title: "Bike intervals",
          block_kind: "hiit_interval",
          dose_class: "vigorous",
          planned_duration_minutes: 12
        )
        intervals.exercise_prescriptions.build(
          exercise: bike,
          position: 1,
          performance_kind: "interval",
          dose_class: "vigorous",
          sets_count: 4,
          work_seconds: 60,
          rest_seconds: 60,
          target_heart_rate_min: 75,
          target_heart_rate_max: 85,
          target_heart_rate_unit: "percent_max",
          target_rpe: 8
        )
      end
      conditioning.save!

      session = household.training_sessions.find_by(person: alex, workout_template: workout)
      session ||= TrainingSession.start_from(template: workout, person: alex, performed_on: today)
      session.update!(
        performed_on: today,
        started_at: Time.zone.local(today.year, today.month, today.day, 7),
        notes: "Felt steady overall; recorded exercise feedback for the next plan."
      )
      session.training_session_blocks.each do |block|
        block.training_session_exercises.each do |session_exercise|
          session_exercise.training_sets.each do |set|
            if session_exercise.snapshot_performance_kind_duration?
              set.update!(
                completed: true,
                duration_seconds: 1_800,
                average_heart_rate_bpm: 122,
                peak_heart_rate_bpm: 134,
                rpe: 5,
                notes: "Conversational throughout."
              )
            else
              set.update!(
                completed: true,
                reps: 8,
                load_amount: 20,
                load_unit: "kg",
                rpe: 7,
                rir: 2,
                notes: "Controlled tempo."
              )
            end
          end
        end
      end
      session.training_session_blocks.first.training_session_exercises.first.update!(
        difficulty: "about_right",
        soreness_or_pain: "Mild left-knee awareness; no sharp pain.",
        substitution: "Used a box as a depth target.",
        next_time_adjustment: "Keep the same load and reassess comfort.",
        notes: "This feedback is available to the coach for later adjustments."
      )
      session.complete! unless session.completed?

      active_session = household.training_sessions.find_by(
        person: alex,
        workout_template: conditioning,
        completed_at: nil
      )
      active_session ||= TrainingSession.start_from(template: conditioning, person: alex, performed_on: today)
      active_session.update!(
        performed_on: today,
        started_at: Time.zone.local(today.year, today.month, today.day, 17, 30),
        notes: "Started after work; performance rows are ready to record."
      )

      household.planned_workouts.find_or_initialize_by(training_session: session).update!(
        household:,
        person: alex,
        workout_template: workout,
        scheduled_on: today
      )
      household.planned_workouts.find_or_initialize_by(training_session: active_session).update!(
        household:,
        person: alex,
        workout_template: conditioning,
        scheduled_on: today
      )
      household.planned_workouts.find_or_initialize_by(
        person: alex,
        workout_template: workout,
        training_session: nil
      ).update!(household:, scheduled_on: today + 1.day)

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

      sunlight = household.habits.find_or_initialize_by(name: "Morning sunlight")
      sunlight.description = "Step outside for morning light when practical."
      sunlight.save!

      alex_water = alex.person_habits.find_or_create_by!(habit: hydration)
      alex_water.ensure_target_rows
      alex_water.person_habit_metrics.find { |target| target.habit_metric.key == "completed" }.boolean_value = true
      alex_water.save!

      alex_movement = alex.person_habits.find_or_create_by!(habit: movement)
      alex_movement.ensure_target_rows
      alex_movement.person_habit_metrics.find { |target| target.habit_metric.key == "duration" }.duration_value = 10
      alex_movement.save!

      alex.person_habits.find_or_create_by!(habit: sunlight)

      sam_movement = sam.person_habits.find_or_create_by!(habit: movement)
      sam_movement.ensure_target_rows
      sam_movement.person_habit_metrics.find { |target| target.habit_metric.key == "duration" }.duration_value = 10
      sam_movement.save!

      [
        [ alex_water, today, { "completed" => { boolean_value: true } } ],
        [ alex_movement, week_start, { "duration" => { duration_value: 12 } } ],
        [ sam_movement, week_start, { "duration" => { duration_value: 10 } } ]
      ].each do |person_habit, checked_on, values|
        check_in = person_habit.habit_check_ins.find_or_initialize_by(checked_on:)
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
