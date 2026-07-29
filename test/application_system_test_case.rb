require "test_helper"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  include ActiveJob::TestHelper
  include ActiveSupport::Testing::TimeHelpers

  driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 1400 ]

  private
    def sign_in_via_browser(user)
      visit_and_wait_for_path new_session_path
      fill_in_and_wait_for_value "Email address", user.email_address
      fill_in_and_wait_for_value "Password", "password"
      click_button_and_wait_for_path "Sign in", root_path
    end

    def switch_person_via_browser(person)
      click_button_and_wait_for_path "Switch to #{person.name}", root_path
    end

    def sign_in_and_open_meals(user)
      sign_in_via_browser user
      click_link_and_wait_for_path "Meals", meal_week_path
      assert_selector "h1", text: "Meals"
      assert_text "July 27, 2026"
      assert_text "PLANNED"
      assert_text "EATEN"
    end

    def visit_and_wait_for_path(path)
      visit path
      page.has_current_path?(path, wait: 5)
      assert_current_path path
      assert_no_selector "html[aria-busy='true']"
    end

    def click_link_and_wait_for_path(label, path)
      link = find_link(label)
      link.click
      page.has_current_path?(path, wait: 5)
      assert_current_path path
      assert_no_selector "html[aria-busy='true']"
    end

    def click_button_and_wait_for_path(label, path)
      button = find_button(label)
      button.click
      page.has_current_path?(path, wait: 5)
      assert_current_path path
      assert_no_selector "html[aria-busy='true']"
    end

    def click_button_and_wait_for_text(label, value)
      button = find_button(label)
      button.click
      page.has_text?(value, wait: 5)
      assert_text value
      assert_no_selector "html[aria-busy='true']"
    end

    def click_button_and_wait_for_count(label, selector, count)
      click_element_and_wait_for_count find_button(label), selector, count
    end

    def click_element_and_wait_for_count(element, selector, count)
      element.click
      assert_selector selector, count: count, wait: 5
      assert_no_selector "html[aria-busy='true']"
    end

    def click_button_and_wait_for_absence(label, selector, text)
      button = find_button(label)
      button.click
      assert_no_selector selector, text: text, wait: 5
      assert_no_selector "html[aria-busy='true']"
    end

    def fill_in_and_wait_for_value(label, value)
      set_and_wait find_field(label), value
    end

    def select_and_wait(option, from:)
      select option, from: from
      page.has_select?(from, selected: option, wait: 5)
      assert_select from, selected: option
    end

    def set_and_wait(field, value)
      field.click
      field.send_keys(value)
      page.has_field?(field[:id], with: value, wait: 5)
      assert_equal value, field.value
      assert_no_selector "html[aria-busy='true']"
    end
end
