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
        { label: "Activities", path: activity_overview_path, icon_name: "bolt", active: primary_navigation_area == :activities }
      ].freeze
      @secondary_navigation = secondary_navigation_items
    end

    def primary_navigation_area
      return :meals if %w[meal_weeks planned_meals meal_logs recipes shopping_lists].include?(controller_name)
      return :activities if %w[
        activity_overviews training_weeks weekly_dose_targets training_sessions
        recovery_days habit_check_ins habits person_habits workout_templates exercises
      ].include?(controller_name)
      return :today if controller_name == "todays"

      nil
    end

    def secondary_navigation_items
      items = case primary_navigation_area
      when :meals
        [
          [ "Week", meal_week_path, %w[meal_weeks planned_meals meal_logs] ],
          [ "Recipes", recipes_path, %w[recipes] ],
          [ "Shopping", shopping_list_path, %w[shopping_lists] ]
        ]
      when :activities
        [
          [ "Overview", activity_overview_path, %w[activity_overviews] ],
          [ "Training", training_week_path, %w[training_weeks training_sessions weekly_dose_targets] ],
          [ "Recovery", recovery_day_path, %w[recovery_days habit_check_ins person_habits habits] ],
          [ "Templates", workout_templates_path, %w[workout_templates] ],
          [ "Exercises", exercises_path, %w[exercises] ]
        ]
      else
        []
      end

      items.map do |label, path, controllers|
        { label: label, path: path, active: controllers.include?(controller_name) }.freeze
      end.freeze
    end
end
