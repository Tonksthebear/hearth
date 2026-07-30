module TailwindplusElementsComponents
  class FormBuilder < ActionView::Helpers::FormBuilder
    # Select method - mimics Rails form.select API.
    # Accepts raw choice arrays or elements_options_for_select output.
    #
    #   form.elements_select :person, [["Wade", 1], ["Tom", 2]]
    #   form.elements_select :person, elements_options_for_select([["Wade", 1], ["Tom", 2]], @person.id)
    #   form.elements_select :person, elements_options_from_collection_for_select(Person.all, :id, :name)
    #   form.elements_select(:person) { |s| s.button { ... } + s.menu { ... } }
    #
    def elements_select(method, choices = nil, options = {}, html_options = {}, &block)
      selected_value = @object&.public_send(method)

      field_options = {
        name: field_name(method),
        id: field_id(method),
        value: selected_value || ""
      }

      field_options[:prompt] = options[:prompt] if options[:prompt]
      field_options[:include_blank] = options[:include_blank] if options.key?(:include_blank)
      field_options[:required] = options[:required] if options[:required]
      field_options.merge!(html_options)

      variant = field_options.delete(:variant) || :default

      html = if choices.present? && block.nil?
        choice_data = case choices
        when ElementsOptionCollection, ElementsGroupedOptionCollection
          choices
        else
          normalized = normalize_choices(choices)
          @template.elements_options_for_select(normalized, selected_value)
        end

        @template.render Elements::SelectComponent.new(variant: variant, **field_options) do |select|
          @template.safe_join([
            select.button { |b|
              @template.safe_join([
                b.selected_content,
                chevron_icon(variant)
              ])
            },
            select.menu {
              @template.render_choices(select, choice_data)
            }
          ])
        end
      else
        @template.render Elements::SelectComponent.new(variant: variant, **field_options), &block
      end

      error_wrapping(method, html)
    end

    # Toggle method - mimics Rails form.check_box API but renders ToggleComponent.
    #
    #   form.toggle :active
    #   form.toggle :active, style: :short
    #   form.toggle(:active) { |t| t.off_icon { ... } + t.on_icon { ... } }
    #
    def toggle(method, options = {}, checked_value = "1", unchecked_value = "0", &block)
      current_value = @object&.public_send(method)

      is_checked = case current_value
      when checked_value, true, "true", 1, "1"
        true
      else
        false
      end

      style = options.delete(:style) || :simple

      field_options = {
        id: field_id(method),
        value: checked_value,
        checked: is_checked
      }
      field_options.merge!(options)

      hidden_field_tag = @template.tag.input(
        type: "hidden",
        name: field_name(method),
        value: unchecked_value,
        autocomplete: "off"
      )

      toggle_html = hidden_field_tag + @template.render(Elements::ToggleComponent.new(field_name(method), style: style, **field_options), &block)
      error_wrapping_toggle(method, toggle_html)
    end

    # Autocomplete method - text field with filtered suggestions.
    # Accepts raw choice arrays or elements_options_for_select output.
    #
    #   form.elements_autocomplete :assignee, ["Wade", "Tom", "Devon"]
    #   form.elements_autocomplete :assignee, elements_options_from_collection_for_select(Person.all, :id, :name)
    #   form.elements_autocomplete(:assignee) { |ac| ac.menu { ... } }
    #
    def elements_autocomplete(method, choices = nil, options = {}, html_options = {}, &block)
      selected_value = options.key?(:value) ? options.delete(:value) : @object&.public_send(method)
      multiple = html_options[:multiple] || options[:multiple]

      field_options = {
        name: multiple ? field_name(method, multiple: true) : field_name(method),
        id: field_id(method)
      }
      field_options.merge!(html_options)

      has_errors = @object&.errors&.[](method)&.any?
      field_options["aria-invalid"] = "true" if has_errors

      create = options.delete(:create) || false
      create_text = options.delete(:create_text)
      settings = options.delete(:settings) || {}
      events = options.delete(:events)
      options.delete(:anchor)
      options.delete(:strict)
      options.delete(:multiple)
      field_options[:multiple] = true if multiple
      field_options.merge!(options)

      html = if choices.present? && block.nil?
        choice_data = case choices
        when ElementsOptionCollection, ElementsGroupedOptionCollection
          choices
        else
          @template.elements_options_for_select(choices)
        end

        @template.render Elements::AutocompleteComponent.new(create: create, create_text: create_text, settings: settings, events: events, **field_options) do |ac|
          ac.menu {
            @template.render_choices(ac, choice_data, selected_value)
          }
        end
      else
        @template.render Elements::AutocompleteComponent.new(create: create, create_text: create_text, settings: settings, events: events, **field_options), &block
      end

      error_wrapping(method, html)
    end

    private

    ErrorInstance = Struct.new(:error_message)

    def error_wrapping(method, html)
      errors = @object&.errors&.[](method)
      if errors.present?
        ActionView::Base.field_error_proc.call(html, ErrorInstance.new(errors))
      else
        html
      end
    end

    # Toggle needs special handling: the hidden input and toggle div are siblings,
    # so we wrap them in a contents div with aria-invalid for the in-[aria-invalid]:
    # cascade. field_error_proc skips aria-invalid injection when already present
    # and just appends the error message.
    def error_wrapping_toggle(method, html)
      errors = @object&.errors&.[](method)
      if errors.present?
        wrapped = @template.content_tag(:div, html, "aria-invalid": "true", class: "contents")
        ActionView::Base.field_error_proc.call(wrapped, ErrorInstance.new(errors))
      else
        html
      end
    end

    def normalize_choices(choices)
      choices.map do |choice|
        if choice.is_a?(Hash) && choice.key?(:value)
          text = choice[:text] || choice[:display] || choice[:value]
          [ text, choice[:value] ]
        else
          choice
        end
      end
    end

    def chevron_icon(variant)
      @template.icon("chevron-up-down", variant: :mini, class: { select: { variant => :icon } })
    end

    public

    alias_method :element_select, :elements_select
    alias_method :element_autocomplete, :elements_autocomplete
  end
end
