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
    end

    def primary_navigation_area
      return :meals if %w[meal_weeks planned_meals meal_logs recipes shopping_lists].include?(controller_name)
      return :activities if %w[
        activity_overviews training_weeks weekly_dose_targets training_sessions
        recovery_days habit_check_ins habits person_habits workout_templates exercises
      ].include?(controller_name)

      :today
    end
end
