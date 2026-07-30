require "application_system_test_case"

class HouseholdPeopleAndPersonContextTest < ApplicationSystemTestCase
  test "interactive text and tinted panels retain dark mode contrast" do
    travel_to Time.zone.local(2026, 7, 27, 12) do
      prepare_household_week_habits
      page.driver.browser.execute_cdp(
        "Emulation.setEmulatedMedia",
        features: [ { name: "prefers-color-scheme", value: "light" } ]
      )
      sign_in_via_browser users(:one)

      week_link = find_link("Previous week", visible: :visible)
      week_link_classes = week_link[:class]
      light_week_color = computed_color(week_link)

      page.driver.browser.execute_cdp(
        "Emulation.setEmulatedMedia",
        features: [ { name: "prefers-color-scheme", value: "dark" } ]
      )
      dark_week_color = computed_color(week_link)
      assert_contrast week_link
      assert_contrast find("#household-plans li p.font-semibold", match: :first)
      assert_contrast find("span", text: "History only", match: :first)

      visit_and_wait_for_path new_recipe_path
      assert_contrast find("label", text: "Amount", match: :prefer_exact)
      assert_contrast find("label", text: "Step", match: :prefer_exact)
      cancel_link = find_link("Cancel", visible: :visible)
      cancel_link_classes = cancel_link[:class]
      dark_cancel_color = computed_color(cancel_link)

      visit_and_wait_for_path edit_workout_template_path(workout_templates(:balanced))
      assert_contrast find("section h3", text: /Block \d+/, match: :first)

      page.driver.browser.execute_cdp(
        "Emulation.setEmulatedMedia",
        features: [ { name: "prefers-color-scheme", value: "light" } ]
      )
      visit_and_wait_for_path new_recipe_path
      light_cancel_color = computed_color(find_link("Cancel", visible: :visible))

      assert_not_equal light_week_color, dark_week_color
      assert_not_equal light_cancel_color, dark_cancel_color
      assert_includes week_link_classes, "dark:text-primary-300"
      assert_includes cancel_link_classes, "dark:text-gray-300"
    end
  ensure
    page.driver.browser.execute_cdp("Emulation.setEmulatedMedia", features: [])
  end

  test "owner manages a login-less person and switches persistent context" do
    visit new_session_path
    fill_in "Email address", with: users(:one).email_address
    fill_in "Password", with: "password"
    click_button_and_wait_for_path "Sign in", root_path

    click_link_and_wait_for_path "Manage people", people_path
    assert_selector "section[aria-labelledby='people-heading'] h1", text: "People"
    click_link_and_wait_for_path "Add person", new_person_path
    assert_selector "section[aria-labelledby='new-person-heading'] h1", text: "Add person"
    assert_no_selector "html[aria-busy='true']"
    fill_in_and_wait_for_value "Name", "Taylor"
    assert_field "Name", with: "Taylor"
    click_button_and_wait_for_path "Create Person", people_path

    assert_selector "section[aria-labelledby='people-heading'] li", text: "Taylor"
    person = Person.find_by!(name: "Taylor")
    assert_no_selector "html[aria-busy='true']"
    click_element_and_wait_for_path find("a[aria-label='Edit Taylor']"), edit_person_path(person)
    assert_no_selector "html[aria-busy='true']"
    fill_in_and_wait_for_value "Name", "Taylor Updated"
    assert_field "Name", with: "Taylor Updated"
    click_button_and_wait_for_path "Update Person", people_path

    assert_selector "section[aria-labelledby='people-heading'] li", text: "Taylor Updated"
    assert_nil person.reload.user

    assert_no_selector "html[aria-busy='true']"
    switch_person_via_browser person
    assert_selector "article[data-current-person='true'] h3", text: "Taylor Updated"
    assert_selector "[data-household-name]", text: /#{Regexp.escape(households(:home).name)}/i

    assert_no_selector "html[aria-busy='true']"
    click_link_and_wait_for_path "Manage people", people_path
    assert_selector "section[aria-labelledby='people-heading'] h1", text: "People"
    assert_no_selector "html[aria-busy='true']"
    click_link_and_wait_for_path "Hearth", root_path
    assert_selector "article[data-current-person='true'] h3", text: "Taylor Updated"
    assert_no_selector "article[data-current-person='true'] h3", text: people(:one).name

    assert_no_selector "html[aria-busy='true']"
    switch_person_via_browser people(:one)
    assert_selector "article[data-current-person='true'] h3", text: people(:one).name, wait: 5
    assert_no_selector "article[data-current-person='true'] h3", text: "Taylor Updated"
  end

  private
    def computed_color(element)
      page.evaluate_script("getComputedStyle(arguments[0]).color", element)
    end

    def assert_contrast(element, minimum: 4.5)
      ratio = page.evaluate_script(<<~JAVASCRIPT, element)
        ((sample) => {
        const canvas = document.createElement("canvas")
        canvas.width = canvas.height = 1
        const context = canvas.getContext("2d", { willReadFrequently: true })

        const rgba = (cssColor) => {
          context.clearRect(0, 0, 1, 1)
          context.fillStyle = "#000"
          context.fillStyle = cssColor
          context.fillRect(0, 0, 1, 1)
          return Array.from(context.getImageData(0, 0, 1, 1).data)
        }

        const composite = (foreground, background) => {
          const foregroundAlpha = foreground[3] / 255
          const backgroundAlpha = background[3] / 255
          const alpha = foregroundAlpha + backgroundAlpha * (1 - foregroundAlpha)
          const channel = (index) =>
            (foreground[index] * foregroundAlpha +
              background[index] * backgroundAlpha * (1 - foregroundAlpha)) / alpha
          return [channel(0), channel(1), channel(2), alpha * 255]
        }

        const ancestors = []
        for (let node = sample; node; node = node.parentElement) ancestors.unshift(node)
        const background = ancestors.reduce((color, node) => {
          return composite(rgba(getComputedStyle(node).backgroundColor), color)
        }, [255, 255, 255, 255])
        const foreground = composite(rgba(getComputedStyle(sample).color), background)

        const luminance = (color) => {
          const channels = color.slice(0, 3).map((channel) => {
            const value = channel / 255
            return value <= 0.04045 ? value / 12.92 : ((value + 0.055) / 1.055) ** 2.4
          })
          return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2]
        }

        const foregroundLuminance = luminance(foreground)
        const backgroundLuminance = luminance(background)
        return (Math.max(foregroundLuminance, backgroundLuminance) + 0.05) /
          (Math.min(foregroundLuminance, backgroundLuminance) + 0.05)
        })(arguments[0])
      JAVASCRIPT

      assert_operator ratio, :>=, minimum,
        "Expected #{element.text.inspect} contrast #{ratio.round(2)} to be at least #{minimum}:1"
    end
end
