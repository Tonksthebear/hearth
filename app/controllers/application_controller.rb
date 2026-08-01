class ApplicationController < ActionController::Base
  include Authentication
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  before_action :prepare_authenticated_context

  private
    def prepare_authenticated_context
      return unless authenticated?

      establish_current_context
      @household = Current.household
      @current_person = Current.person
      @household_people = Current.household.people.order(:name)
      @primary_navigation = [
        { label: "Today", path: root_path, icon_name: "home", active: primary_navigation_area == :today },
        { label: "Meals", path: meal_week_path, icon_name: "calendar-days", active: primary_navigation_area == :meals },
        { label: "Activities", path: activity_week_path, icon_name: "bolt", active: primary_navigation_area == :activities }
      ].freeze
      @secondary_navigation = secondary_navigation_items
    end

    def primary_navigation_area
      return :meals if %w[
        meal_weeks planned_meals planned_meal/meals meals recipes shopping_lists
        shopping_list_items shopping_list_item/completions
      ].include?(controller_path)
      return :activities if %w[
        activity_weeks activity_libraries activity_histories planned_workouts planned_workout/skips
        training_weeks weekly_dose_targets training_sessions
        recovery_days habit_check_ins habits person_habits workout_templates exercises
      ].include?(controller_path)
      return :today if controller_path == "todays"

      nil
    end

    def secondary_navigation_items
      items = case primary_navigation_area
      when :meals
        [
          [ "Week", meal_week_path, %w[meal_weeks planned_meals planned_meal/meals meals] ],
          [ "Recipes", recipes_path, %w[recipes] ],
          [ "Shopping", shopping_list_path, %w[shopping_lists shopping_list_items shopping_list_item/completions], { turbo_prefetch: false } ]
        ]
      when :activities
        [
          [ "Week", activity_week_path, %w[activity_weeks planned_workouts planned_workout/skips training_sessions training_weeks weekly_dose_targets] ],
          [ "Library", activity_library_path, %w[activity_libraries recovery_days habit_check_ins habits person_habits workout_templates exercises] ],
          [ "History", activity_history_path, %w[activity_histories] ]
        ]
      else
        []
      end

      items.map do |label, path, controllers, data|
        { label: label, path: path, active: controllers.include?(controller_path), data: data }.freeze
      end.freeze
    end
end
