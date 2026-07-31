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
      find_button("Open person menu").click
      click_button_and_wait_for_path "Switch to #{person.name}", root_path
      assert_selector "h1", text: "Today", wait: 5
    end

    def visit_and_wait_for_path(path)
      visit path
      page.has_current_path?(path, wait: 5)
      assert_current_path path
      assert_no_selector "html[aria-busy='true']"
      assert page.document.has_css?("html[data-elements-ready='true']", visible: :all, wait: 5)
    end

    def click_link_and_wait_for_path(label, path, **options)
      open_sidebar_if_needed(label)
      link = find_link(label, **options)
      link.click
      assert_current_path path, wait: 5
      assert_no_selector "html[aria-busy='true']"
      assert page.document.has_css?("html[data-elements-ready='true']", visible: :all, wait: 5)
    end

    def open_sidebar_if_needed(label)
      return if page.has_link?(label, visible: :visible, wait: 0)
      return unless page.has_button?("Open sidebar", visible: :visible, wait: 0)

      find_button("Open sidebar").click
      assert_link label, visible: :visible, wait: 5
    end

    def click_element_and_wait_for_path(element, path)
      element.click
      assert_current_path path, wait: 5
      assert_no_selector "html[aria-busy='true']"
      assert page.document.has_css?("html[data-elements-ready='true']", visible: :all, wait: 5)
    end

    def click_button_and_wait_for_path(label, path)
      button = find_button(label)
      webdriver_click(button)
      unless page.has_current_path?(path, wait: 5)
        javascript_click(button)
      end
      assert_current_path path
      assert_no_selector "html[aria-busy='true']"
      assert page.document.has_css?("html[data-elements-ready='true']", visible: :all, wait: 5)
    end

    def click_button_and_wait_for_text(label, value)
      click_element_and_wait_for_text find_button(label), value
    end

    def click_element_and_wait_for_text(element, value)
      webdriver_click(element)
      javascript_click(element) unless page.has_text?(value, wait: 5)
      assert_text value
      assert_no_selector "html[aria-busy='true']"
    end

    def click_button_and_wait_for_count(label, selector, count)
      click_element_and_wait_for_count find_button(label), selector, count
    end

    def click_element_and_wait_for_count(element, selector, count)
      webdriver_click(element)
      unless page.has_selector?(selector, count: count, wait: 5)
        javascript_click(element)
      end
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
      control = find_by_id(from, visible: :all, wait: 0)
    rescue Capybara::ElementNotFound
      field_id = find("label", text: from, match: :prefer_exact)[:for]
      control = find_by_id(field_id, visible: :all)
      choose_elements_option(control, option)
    else
      choose_elements_option(control, option)
    end

    def choose_elements_option(control, option)
      if control.tag_name == "button" && control.has_xpath?("ancestor::el-select")
        control = control.find(:xpath, "ancestor::el-select")
      end

      if control.tag_name == "el-select"
        within control do
          button = find("button")
          button.click
          if page.has_selector?("el-option", text: option, exact_text: true, visible: :visible, wait: 5)
            find("el-option", text: option, exact_text: true, visible: :visible).click
          else
            selected_option = find("el-option", text: option, exact_text: true, visible: :all)
            page.execute_script("arguments[0].click()", selected_option.native)
          end
        end
        assert_text option, wait: 5
        assert_equal option, control.find("el-selectedcontent").text
      elsif control.matches_css?("[data-elements-autocomplete]")
        slim_select = control.sibling(".ss-main")
        slim_select.click
        content = find(".ss-content[data-id='#{slim_select["data-id"]}']", visible: :visible, wait: 5)
        within content do
          search = find("input[type='search']", visible: :visible)
          search.send_keys(option)
          assert_selector ".ss-option", text: option, exact_text: true, count: 1, visible: :visible, wait: 5
          assert_selector ".ss-option", count: 1, visible: :visible, wait: 5
          search.send_keys(:arrow_down, :enter)
          search.send_keys(:escape) if content.matches_css?(".ss-open")
        end
        assert_equal option, slim_select.find(".ss-single").text
        assert_equal option, control.find("option:checked", visible: :all).text
        assert_no_selector ".ss-content[data-id='#{slim_select["data-id"]}'].ss-open", wait: 5
      else
        control.select option
        assert_equal option, control.find("option:checked").text
      end
    end

    def select_element_and_wait(label, option)
      field_id = find("label", text: label, match: :prefer_exact)[:for]
      select_and_wait option, from: field_id
    end

    def set_and_wait(field, value)
      field_id = field[:id]

      3.times do
        current_field = find_by_id(field_id)
        current_field.set("")
        value.each_char { |character| current_field.send_keys(character) }
        break if page.has_field?(field_id, with: value, wait: 1)
      end

      unless page.has_field?(field_id, with: value, wait: 0)
        current_field = find_by_id(field_id)
        page.execute_script(
          "arguments[0].value = arguments[1]; arguments[0].dispatchEvent(new Event('input', { bubbles: true })); arguments[0].dispatchEvent(new Event('change', { bubbles: true }))",
          current_field.native,
          value
        )
      end

      assert_field field_id, with: value, wait: 5
      assert_equal value, find_by_id(field_id).value
      assert_no_selector "html[aria-busy='true']"
    end

    def javascript_click(element)
      page.execute_script("arguments[0].click()", element.native)
    rescue Selenium::WebDriver::Error::StaleElementReferenceError
      # The original interaction completed while its expected page state was still rendering.
    end

    def webdriver_click(element)
      element.click
    rescue Selenium::WebDriver::Error::StaleElementReferenceError
      # Turbo replaced the clicked element while WebDriver was returning from the interaction.
    end

    def check_and_wait(field)
      field_id = field[:id]
      field.check
      assert_field field_id, checked: true, visible: :all, wait: 5
      assert_no_selector "html[aria-busy='true']"
    end
end
