require "test_helper"

class RecoveryDaysControllerTest < ActionDispatch::IntegrationTest
  test "renders targets, current-person values, and inactive history without an action" do
    sign_in_as users(:one)

    get recovery_day_path

    assert_response :success
    assert_select "nav a", text: "Recovery"
    assert_select "#today-person-habit-#{person_habits(:alex_sauna).id}", text: /Your target: 20 minutes/
    assert_select "article", text: /Lights out.*History only/m
    assert_select "#today-person-habit-#{person_habits(:alex_lights_out).id}", count: 0
    assert_select "body", text: /18 minutes/
    assert_select "body", text: /170\.0 °F/
  end

  test "excludes another person's configuration targets values and history" do
    sign_in_as users(:one)

    get recovery_day_path

    assert_response :success
    assert_select "body", text: /Post-meal movement/, count: 0
    assert_select "body", text: /Your target: 15 minutes/, count: 0
    assert_select "body", text: /160\.0 °F/, count: 0
  end
end
