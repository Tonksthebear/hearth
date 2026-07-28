require "test_helper"

class AuthenticationDefaultsTest < ActiveSupport::TestCase
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
      callback.instance_variable_get(:@unless).flat_map do |condition|
        condition.instance_variable_get(:@actions)&.to_a || []
      end
    end
end
