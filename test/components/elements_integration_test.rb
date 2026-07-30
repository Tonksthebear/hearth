require "test_helper"
require "view_component/test_case"

class ElementsIntegrationTest < ViewComponent::TestCase
  test "synced button resolves semantic yass classes without the source engine" do
    render_inline Elements::ButtonComponent.new("Save", color: :primary, size: :md)

    assert_selector "button[type='button']", text: "Save"
    assert_selector "button.bg-primary-600.text-white"
    assert_not defined?(TailwindplusElementsComponents::Engine)
  end

  test "select keeps its native form value and command markup" do
    render_inline Elements::SelectComponent.new(name: "meal[person_id]", value: "2") do |select|
      select.button { |button| button.selected_content("Choose a person") } +
        select.menu { select.option(value: "2", display: "Jordan", selected: true) }
    end

    assert_selector "el-select[name='meal[person_id]'][value='2']"
    assert_selector "button[type='button'] el-selectedcontent", text: "Choose a person"
    assert_selector "el-options[popover]"
    assert_selector "el-option[value='2']", text: "Jordan"
  end

  test "autocomplete renders a native select for SlimSelect enhancement" do
    render_inline Elements::AutocompleteComponent.new(
      name: "meal[person_id]",
      placeholder: "Search people"
    ) do |autocomplete|
      autocomplete.menu { autocomplete.option(value: "2", display: "Jordan", selected: true) }
    end

    assert_selector "select[name='meal[person_id]'][data-elements-autocomplete='true']"
    assert_selector "option[value='2'][selected]", text: "Jordan"
  end

  test "toggle and dialog expose accessible native controls" do
    render_inline Elements::ToggleComponent.new("habit[completed]", checked: true, aria: { label: "Completed" })

    assert_selector "input[type='checkbox'][name='habit[completed]'][checked][aria-label='Completed']"

    render_inline Elements::DialogComponent.new(id: "discard-dialog", open: true) do |dialog|
      dialog.title("Discard draft") +
        dialog.description("This cannot be undone.") +
        dialog.close_button("Cancel", color: :neutral)
    end

    assert_selector "el-dialog[open]"
    assert_selector "dialog#discard-dialog[aria-labelledby='dialog-title']"
    assert_selector "button[command='close'][commandfor='discard-dialog']", text: "Cancel"
  end
end
