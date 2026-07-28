module Setup
  class HouseholdsController < ApplicationController
    allow_unauthenticated_access
    before_action :redirect_if_configured

    def new
      prepare_form
    end

    def create
      @household = Household.bootstrap(
        household_attributes: { name: setup_params[:household_name] },
        person_attributes: { name: setup_params[:person_name] },
        user_attributes: setup_params.slice(:email_address, :password, :password_confirmation)
      )
      @person = @household.people.first
      @user = @person&.user
      @setup_error_messages = @household.setup_error_messages

      if @household.persisted?
        start_new_session_for(@user)
        redirect_to root_path, notice: "Your household is ready."
      else
        render :new, status: :unprocessable_entity
      end
    end

    private
      def prepare_form
        @household = Household.new
        @person = @household.people.build
        @user = @person.build_user
        @setup_error_messages = @household.setup_error_messages
      end

      def setup_params
        params.expect(setup: %i[ household_name person_name email_address password password_confirmation ])
      end

      def redirect_if_configured
        redirect_to root_path, alert: "Household setup is already complete." if Household.configured?
      end
  end
end
