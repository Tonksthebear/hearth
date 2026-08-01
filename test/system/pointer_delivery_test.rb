require "application_system_test_case"

class PointerDeliveryTest < ApplicationSystemTestCase
  test "delivers trusted pointer events after browser emulation resets" do
    visit_and_wait_for_path new_session_path
    clean_state = browser_state

    exercise_pointer_matrix("clean")

    {
      "device-metrics" => -> {
        browser.execute_cdp(
          "Emulation.setDeviceMetricsOverride",
          width: 390,
          height: 900,
          deviceScaleFactor: 1,
          mobile: false
        )
        browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
      },
      "emulated-media" => -> {
        browser.execute_cdp(
          "Emulation.setEmulatedMedia",
          features: [ { name: "prefers-color-scheme", value: "dark" } ]
        )
        browser.execute_cdp("Emulation.setEmulatedMedia", features: [])
      }
    }.each do |mutation, apply_and_clear|
      apply_and_clear.call
      Capybara.reset_sessions!
      visit_and_wait_for_path new_session_path

      assert_equal clean_state, browser_state, "browser state did not recover after #{mutation}"
      exercise_pointer_matrix("after-#{mutation}")
    end
  end

  private
    def exercise_pointer_matrix(label)
      exercise_native_link(label)
      exercise_native_submit(label)
      exercise_elements_select(label)
    end

    def exercise_native_link(label)
      visit_and_wait_for_path new_session_path
      link = find_link("Forgot password?")
      probe = install_event_probe("#{label}-link", link => %w[pointerdown click])
      diagnostics = pointer_diagnostics(link)

      link.click

      assert_current_path new_password_path, wait: 5
      assert_events probe, %w[pointerdown click], trusted: %w[pointerdown click], diagnostics:
    end

    def exercise_native_submit(label)
      visit_and_wait_for_path new_session_path
      fill_in "Email address", with: users(:one).email_address
      fill_in "Password", with: "password"
      button = find_button("Sign in")
      probe = install_event_probe(
        "#{label}-submit",
        button => %w[pointerdown click],
        button.find(:xpath, "ancestor::form") => %w[submit]
      )
      diagnostics = pointer_diagnostics(button)

      button.click

      assert_current_path root_path, wait: 5
      assert_events probe, %w[pointerdown click submit], trusted: %w[pointerdown click submit], diagnostics:
    end

    def exercise_elements_select(label)
      visit_and_wait_for_path activity_week_path
      control = find("el-select[name='planned_workout[workout_template_id]']")
      button = control.find("button")
      probe = install_event_probe("#{label}-elements", button => %w[pointerdown click])
      diagnostics = pointer_diagnostics(button)

      button.click
      option = control.find(
        "el-option",
        text: workout_templates(:balanced).title,
        exact_text: true,
        visible: :visible,
        wait: 5
      )
      extend_event_probe probe, option => %w[pointerdown click], control => %w[change]
      option.click

      assert_equal workout_templates(:balanced).title, control.find("el-selectedcontent").text
      assert_events probe, %w[pointerdown click change],
        trusted: %w[pointerdown click],
        counts: { "pointerdown" => 2, "click" => 2, "change" => 1 },
        diagnostics:
      synchronized_changes = recorded_events(probe).count { |event|
        event["type"] == "change" && event["value"] == workout_templates(:balanced).id.to_s
      }
      assert_equal 1, synchronized_changes
    end

    def install_event_probe(name, targets)
      key = "pointer-delivery:#{name}"
      page.execute_script("sessionStorage.setItem(arguments[0], '[]')", key)
      extend_event_probe key, targets
      key
    end

    def extend_event_probe(key, targets)
      targets.each do |target, events|
        page.execute_script(<<~JAVASCRIPT, target, key, events)
          for (const eventName of arguments[2]) {
            arguments[0].addEventListener(eventName, (event) => {
              const records = JSON.parse(sessionStorage.getItem(arguments[1]) || "[]")
              records.push({
                type: event.type,
                isTrusted: event.isTrusted,
                target: event.target.tagName.toLowerCase(),
                value: event.target.value
              })
              sessionStorage.setItem(arguments[1], JSON.stringify(records))
            }, { capture: true })
          }
        JAVASCRIPT
      end
    end

    def assert_events(key, expected_types, trusted:, diagnostics:, counts: expected_types.index_with(1))
      events = recorded_events(key)

      expected_types.each do |type|
        assert_equal counts.fetch(type), events.count { |event| event["type"] == type },
          "unexpected #{type} count; events=#{events.inspect}; diagnostics=#{diagnostics.inspect}"
      end

      trusted.each do |type|
        assert events.any? { |event| event["type"] == type && event["isTrusted"] },
          "expected trusted #{type}; events=#{events.inspect}; diagnostics=#{diagnostics.inspect}"
      end
    end

    def recorded_events(key)
      page.evaluate_script("JSON.parse(sessionStorage.getItem(arguments[0]) || '[]')", key)
    end

    def pointer_diagnostics(element)
      page.evaluate_script(<<~JAVASCRIPT, element)
        ((target) => {
          const rect = target.getBoundingClientRect()
          const centerX = rect.left + rect.width / 2
          const centerY = rect.top + rect.height / 2
          const hit = document.elementFromPoint(centerX, centerY)

          return {
            target: target.tagName.toLowerCase(),
            disabled: target.disabled || false,
            rect: { x: rect.x, y: rect.y, width: rect.width, height: rect.height },
            centerHit: hit && `${hit.tagName.toLowerCase()}#${hit.id}`,
            targetOwnsCenter: hit === target || target.contains(hit),
            activeElement: document.activeElement && document.activeElement.tagName.toLowerCase(),
            hasFocus: document.hasFocus(),
            openDialogs: document.querySelectorAll("dialog[open], [popover]:popover-open").length,
            state: {
              innerWidth: window.innerWidth,
              innerHeight: window.innerHeight,
              visualViewport: window.visualViewport && {
                width: window.visualViewport.width,
                height: window.visualViewport.height,
                offsetLeft: window.visualViewport.offsetLeft,
                offsetTop: window.visualViewport.offsetTop,
                scale: window.visualViewport.scale
              },
              dark: matchMedia("(prefers-color-scheme: dark)").matches
            }
          }
        })(arguments[0])
      JAVASCRIPT
    end

    def browser_state
      page.evaluate_script(<<~JAVASCRIPT)
        ({
          innerWidth: window.innerWidth,
          innerHeight: window.innerHeight,
          visualViewport: window.visualViewport && {
            width: window.visualViewport.width,
            height: window.visualViewport.height,
            offsetLeft: window.visualViewport.offsetLeft,
            offsetTop: window.visualViewport.offsetTop,
            scale: window.visualViewport.scale
          },
          dark: matchMedia("(prefers-color-scheme: dark)").matches
        })
      JAVASCRIPT
    end

    def browser
      page.driver.browser
    end
end
