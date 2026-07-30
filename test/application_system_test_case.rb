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
      page.execute_script("arguments[0].click()", link)
      assert_current_path path, wait: 5
      assert_no_selector "html[aria-busy='true']"
      assert page.document.has_css?("html[data-elements-ready='true']", visible: :all, wait: 5)
    end

    def open_sidebar_if_needed(label)
      return if page.has_link?(label, visible: :visible, wait: 0)
      return unless page.has_button?("Open sidebar", visible: :visible, wait: 0)

      page.execute_script("arguments[0].click()", find_button("Open sidebar"))
      assert_link label, visible: :visible, wait: 5
    end

    def click_element_and_wait_for_path(element, path)
      page.execute_script("arguments[0].click()", element)
      assert_current_path path, wait: 5
      assert_no_selector "html[aria-busy='true']"
      assert page.document.has_css?("html[data-elements-ready='true']", visible: :all, wait: 5)
    end

    def click_button_and_wait_for_path(label, path)
      button = find_button(label)
      page.execute_script("arguments[0].click()", button)
      page.has_current_path?(path, wait: 5)
      assert_current_path path
      assert_no_selector "html[aria-busy='true']"
      assert page.document.has_css?("html[data-elements-ready='true']", visible: :all, wait: 5)
    end

    def click_button_and_wait_for_text(label, value)
      button = find_button(label)
      page.execute_script("arguments[0].click()", button)
      page.has_text?(value, wait: 5)
      assert_text value
      assert_no_selector "html[aria-busy='true']"
    end

    def click_button_and_wait_for_count(label, selector, count)
      click_element_and_wait_for_count find_button(label), selector, count
    end

    def click_element_and_wait_for_count(element, selector, count)
      page.execute_script("arguments[0].click()", element)
      assert_selector selector, count: count, wait: 5
      assert_no_selector "html[aria-busy='true']"
    end

    def click_button_and_wait_for_absence(label, selector, text)
      button = find_button(label)
      page.execute_script("arguments[0].click()", button)
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
          button.send_keys(:space) unless page.has_css?("el-option", text: option, visible: :visible, wait: 1)
          unless page.has_css?("el-option", text: option, visible: :visible, wait: 1)
            options = find("el-options", visible: :all)
            page.execute_script("arguments[0].showPopover()", options)
          end
          selected_option = find("el-option", text: option, visible: :visible)
          selected_option.click
          unless control.find("el-selectedcontent").has_text?(option, wait: 1)
            page.execute_script("arguments[0].value = arguments[1]", control, selected_option[:value])
          end
          page.execute_script("arguments[0].hidePopover()", find("el-options", visible: :all))
        end
        assert_equal option, control.find("el-selectedcontent").text
      elsif control.matches_css?("[data-elements-autocomplete]")
        slim_select = control.sibling(".ss-main")
        page.execute_script("arguments[0].slim.open()", control)
        selected_option = find(".ss-option", text: option, visible: :visible, wait: 5)
        page.execute_script("arguments[0].click()", selected_option)
        unless control.find("option:checked", visible: :all).has_text?(option, wait: 1)
          selected_option = control.find("option", text: option, visible: :all)
          page.execute_script(<<~JS, control, selected_option[:value])
            const select = arguments[0]
            select.value = arguments[1]
            select.dispatchEvent(new Event("change", { bubbles: true }))
          JS
        end
        page.execute_script("arguments[0].slim?.close()", control)
        assert_equal option, slim_select.find(".ss-single").text
        assert_equal option, control.find("option:checked", visible: :all).text
        assert_no_selector ".ss-content.ss-open", wait: 5
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
        page.execute_script(<<~JS, current_field, value)
          const field = arguments[0]
          field.value = arguments[1]
          field.dispatchEvent(new Event("input", { bubbles: true }))
          field.dispatchEvent(new Event("change", { bubbles: true }))
        JS
        break if page.has_field?(field_id, with: value, wait: 1)
      end

      assert_field field_id, with: value, wait: 5
      assert_equal value, find_by_id(field_id).value
      assert_no_selector "html[aria-busy='true']"
    end

    def check_and_wait(field)
      field_id = field[:id]
      current_field = find_by_id(field_id, visible: :all)
      page.execute_script(<<~JS, current_field)
        const field = arguments[0]
        field.checked = true
        field.dispatchEvent(new Event("input", { bubbles: true }))
        field.dispatchEvent(new Event("change", { bubbles: true }))
      JS

      assert_field field_id, checked: true, visible: :all, wait: 5
      assert_no_selector "html[aria-busy='true']"
    end
end
