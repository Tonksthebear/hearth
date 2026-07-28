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
      @person = Current.person
      @household_people = Current.household.people.order(:name)
    end
end
