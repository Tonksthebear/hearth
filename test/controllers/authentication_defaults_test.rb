require "test_helper"

class AuthenticationDefaultsTest < ActiveSupport::TestCase
  UnsupportedAuthenticationCallback = Class.new(StandardError)

  EXPECTED_UNGUARDED_ACTIONS = Set[
    "PasswordsController#create",
    "PasswordsController#edit",
    "PasswordsController#new",
    "PasswordsController#update",
    "SessionsController#create",
    "SessionsController#new",
    "Setup::HouseholdsController#create",
    "Setup::HouseholdsController#new"
  ]

  test "application controllers authenticate by default with an exact public action set" do
    Rails.autoloaders.main.eager_load_dir(Rails.root.join("app/controllers"))

    assert_equal EXPECTED_UNGUARDED_ACTIONS, unguarded_actions
  end

  test "unsupported authentication skip shapes fail loudly" do
    assert_raises UnsupportedAuthenticationCallback do
      skipped_actions(authentication_callback_for(skip_options: { except: :show }))
    end

    assert_raises UnsupportedAuthenticationCallback do
      skipped_actions(authentication_callback_for(skip_options: { if: -> { true } }))
    end
  end

  private
    def unguarded_actions
      ApplicationController.descendants.each_with_object(Set.new) do |controller, actions|
        callback = controller._process_action_callbacks.find do |candidate|
          candidate.kind == :before && candidate.filter == :require_authentication
        end

        public_actions = callback ? skipped_actions(callback) : controller.action_methods
        public_actions.each { |action| actions << "#{controller.name}##{action}" }
      end
    end

    def skipped_actions(callback)
      conditions = callback.instance_variable_get(:@unless)

      if callback.instance_variable_get(:@if).any? || conditions.any? { |condition| !condition.instance_variable_defined?(:@actions) }
        raise UnsupportedAuthenticationCallback, "Authentication skip uses a shape this whitelist cannot inspect"
      end

      conditions.flat_map { |condition| condition.instance_variable_get(:@actions).to_a }
    end

    def authentication_callback_for(skip_options:)
      Class.new(ActionController::Base) do
        before_action :require_authentication
        skip_before_action :require_authentication, **skip_options
      end._process_action_callbacks.find { |callback| callback.filter == :require_authentication }
    end
end
