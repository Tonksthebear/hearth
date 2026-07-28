require "application_system_test_case"
require "uri"

class PasswordRecoveryTest < ApplicationSystemTestCase
  test "owner follows the delivered reset link and signs in with the new password" do
    visit new_session_path
    click_link "Forgot password?"

    fill_in "Email address", with: users(:one).email_address
    perform_enqueued_jobs do
      click_button "Email reset instructions"
      assert_selector "#notice", text: /reset instructions sent/
    end
    perform_enqueued_jobs

    assert_equal 1, ActionMailer::Base.deliveries.size
    reset_url = ActionMailer::Base.deliveries.last.html_part.body.decoded[/href="([^"]+)"/, 1]
    visit URI.parse(reset_url).request_uri

    assert_selector "h1", text: "Update your password"
    fill_in "Enter new password", with: "new password"
    fill_in "Repeat new password", with: "new password"
    click_button "Save"

    assert_selector "#notice", text: "Password has been reset."
    fill_in "Email address", with: users(:one).email_address
    fill_in "Password", with: "new password"
    click_button "Sign in"

    assert_selector "section[aria-labelledby='household-heading'] h1", text: households(:home).name
  end
end
