require "test_helper"

class ApplicationUiRenderTest < ActiveSupport::TestCase
  test "default builder resolves yass classes for model-backed invalid fields" do
    person = Person.new
    person.errors.add(:name, "can't be blank")

    document = render_inline(<<~ERB, person:)
      <%= form_with model: @person, url: "/people" do |form| %>
        <%= form.label :name, class: :label %>
        <%= form.text_field :name, class: :text_field %>
        <%= form.submit "Save", class: { btn: [ :base, { lg: :base }, { primary: :solid } ] } %>
      <% end %>
    ERB

    assert_equal TailwindplusElementsComponents::FormBuilder, ActionView::Base.default_form_builder
    assert document.at_css("label.block")
    assert document.at_css("input[name='person[name]'][aria-invalid='true'].rounded-md")
    assert document.at_css("input[type='submit'].bg-primary-600")
    assert_includes document.text, "can't be blank"
  end

  test "model-less GET forms keep stable names and Elements controls" do
    document = render_inline(<<~ERB)
      <%= form_with url: "/recipes", method: :get do |form| %>
        <%= form.search_field :q, value: "soup", class: :text_field %>
        <%= form.elements_select :status, [["All", ""], ["Adapted", "adapted"]], {}, value: "adapted" %>
      <% end %>
    ERB

    assert document.at_css("form[method='get']")
    assert document.at_css("input[name='q'][value='soup']")
    assert document.at_css("el-select[name='status'][value='adapted']")
    assert_equal "Adapted", document.at_css("el-select[name='status'] el-selectedcontent").text
    assert document.at_css("el-option[value='adapted']")
  end

  test "Elements selects preserve and display a false boolean value" do
    document = render_inline(<<~ERB)
      <%= form_with url: "/preferences" do |form| %>
        <%= form.elements_select :enabled, [["Yes", true], ["No", false]], {}, value: false %>
      <% end %>
    ERB

    assert document.at_css("el-select[name='enabled'][value='false']")
    assert_equal "No", document.at_css("el-selectedcontent").text
    assert document.at_css("el-option[value='false'][selected]")
  end

  test "autocomplete preserves the native select contract" do
    planned_meal = PlannedMeal.new

    document = render_inline(<<~ERB, planned_meal:)
      <%= form_with model: @planned_meal, url: "/planned_meals" do |form| %>
        <%= form.elements_autocomplete :person_id,
          [["Whole household", ""], ["Alex", "7"]],
          { value: "7" },
          { placeholder: "Whole household" } %>
      <% end %>
    ERB

    assert document.at_css("select#planned_meal_person_id[name='planned_meal[person_id]'][data-elements-autocomplete='true']")
    assert document.at_css("option[value='7'][selected]")
  end

  test "field errors escape user-controlled messages" do
    person = Person.new
    person.errors.add(:name, "<script>alert('no')</script>")

    document = render_inline(<<~ERB, person:)
      <%= form_with model: @person, url: "/people" do |form| %>
        <%= form.text_field :name, class: :text_field %>
      <% end %>
    ERB

    assert_nil document.at_css("script")
    assert_includes document.text, "<script>alert('no')</script>"
  end

  test "shared alerts use the configured Elements treatment and escape messages" do
    document = render_inline(<<~ERB)
      <%= render "layouts/alert",
            id: "example-errors",
            title: "Could not save:",
            messages: ["<script>alert('no')</script>"] %>
    ERB

    alert = document.at_css("#example-errors[role='alert']")
    assert alert
    assert_includes alert["class"], "rounded-md"
    assert_includes alert.text, "<script>alert('no')</script>"
    assert_nil alert.at_css("script")
  end

  private
    def render_inline(template, assigns = {})
      html = ApplicationController.render(
        inline: template,
        assigns: assigns,
        layout: false
      )
      Nokogiri::HTML.fragment(html)
    end
end
