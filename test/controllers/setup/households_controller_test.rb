require "test_helper"

class Setup::HouseholdsControllerTest < ActionDispatch::IntegrationTest
  test "new is available before configuration" do
    clear_installation

    get new_setup_household_path

    assert_response :success
    assert_select "h1", "Create your household"
  end

  test "create bootstraps the installation and signs in the owner" do
    clear_installation

    assert_difference [ "Household.count", "Person.count", "User.count", "Session.count" ], 1 do
      post setup_household_path, params: valid_setup_params
    end

    owner = User.find_by!(email_address: "owner@example.com")
    assert_redirected_to root_path
    assert cookies[:session_id]
    assert_equal owner, Session.order(:created_at).last.user
  end

  test "invalid create renders errors and persists nothing" do
    clear_installation
    params = valid_setup_params
    params[:setup][:person_name] = ""

    assert_no_difference [ "Household.count", "Person.count", "User.count", "Session.count" ] do
      post setup_household_path, params: params
    end

    assert_response :unprocessable_entity
    assert_select "#setup-errors li", count: 1, text: "Your name can't be blank"
    assert_select "#setup-errors", count: 0, text: /People is invalid/
    assert_nil cookies[:session_id]
  end

  test "configured installations reject another setup page or submission" do
    get new_setup_household_path
    assert_redirected_to root_path

    assert_no_difference [ "Household.count", "Person.count", "User.count" ] do
      post setup_household_path, params: valid_setup_params
    end
    assert_redirected_to root_path
  end

  test "a concurrency loser renders setup unavailable without a session" do
    clear_installation
    household = Household.new(name: "Home")
    original_new = Household.method(:new)
    Household.define_singleton_method(:new) { |*| household }
    household.define_singleton_method(:save) { raise ActiveRecord::RecordNotUnique, "duplicate" }

    post setup_household_path, params: valid_setup_params

    assert_response :unprocessable_entity
    assert_select "#setup-errors", /no longer available/
    assert_nil cookies[:session_id]
  ensure
    Household.define_singleton_method(:new, original_new) if original_new
  end

  private
    def valid_setup_params
      {
        setup: {
          household_name: "Home",
          person_name: "Owner",
          email_address: "owner@example.com",
          password: "password",
          password_confirmation: "password"
        }
      }
    end

    def clear_installation
      Session.delete_all
      User.delete_all
      MealLog.delete_all
      PlannedMeal.delete_all
      TrainingSet.delete_all
      TrainingSessionExercise.delete_all
      TrainingSessionBlock.delete_all
      TrainingSession.delete_all
      Person.delete_all
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
