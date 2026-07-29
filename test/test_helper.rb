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
      def clear_installation
        Session.delete_all
        User.delete_all
        MealLog.delete_all
        PlannedMeal.delete_all
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
        RecipeInstruction.delete_all
        RecipeIngredient.delete_all
        Recipe.delete_all
        Household.delete_all
      end
  end
end
