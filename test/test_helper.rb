ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require_relative "test_helpers/session_test_helper"
require_relative "test_helpers/household_week_test_helper"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    private
      def create_runtime_session
        Agent::Session.create!(
          household: households(:home),
          person: people(:two),
          conversation: agent_conversations(:active),
          installation: agent_installations(:local),
          status: "starting",
          external_session_id: nil,
          advertised_capabilities: {},
          authentication_status: "authenticated",
          mcp_authorization_status: "not_configured"
        )
      end

      def clear_installation
        Agent::AuditEvent.delete_all
        Agent::PermissionDecision.delete_all
        Agent::PermissionRequest.delete_all
        Agent::ToolActivity.delete_all
        Agent::Message.delete_all
        Agent::Grant.delete_all
        Agent::Session.delete_all
        Agent::Conversation.delete_all
        Agent::Installation.delete_all
        Agent::Profile.delete_all
        Session.delete_all
        User.delete_all
        RecipeFeedback.delete_all
        MealItemNutrientValue.delete_all
        MealItem.delete_all
        Meal.delete_all
        PlannedMeal.delete_all
        PlannedWorkout.delete_all
        TrainingSet.delete_all
        TrainingSessionExercise.delete_all
        TrainingSessionBlock.delete_all
        TrainingSession.delete_all
        HabitCheckInMeasurement.delete_all
        HabitCheckIn.delete_all
        PersonHabitMetric.delete_all
        PersonHabit.delete_all
        Person.delete_all
        HabitMetric.delete_all
        Habit.delete_all
        ExercisePrescription.delete_all
        WorkoutBlock.delete_all
        WorkoutTemplate.delete_all
        Exercise.delete_all
        RecipeInstructionIngredient.delete_all
        RecipeInstruction.delete_all
        RecipeNutrientValue.delete_all
        RecipeIngredient.delete_all
        IngredientNutrientValue.delete_all
        Ingredient.delete_all
        Recipe.delete_all
        Nutrient.delete_all
        Household.delete_all
      end
  end
end
