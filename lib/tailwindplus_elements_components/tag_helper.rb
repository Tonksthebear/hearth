module TailwindplusElementsComponents
  module TagHelper
    include ActionView::Helpers::FormOptionsHelper

    # Returns structured option data for use with elements_select_tag.
    # Same API as Rails' options_for_select, but returns data instead of HTML.
    #
    #   elements_options_for_select(["Wade", "Tom"])
    #   elements_options_for_select([["Wade", 1], ["Tom", 2]], 1)
    #   elements_options_for_select([["Wade", 1, {disabled: true}]], 1)
    #   elements_options_for_select([["Wade", 1], ["Tom", 2]], selected: 1, disabled: [2])
    #
    def elements_options_for_select(container, selected = nil)
      return container if container.is_a?(ElementsOptionCollection)

      selected, disabled = extract_selected_and_disabled(selected).map do |r|
        Array(r).map(&:to_s)
      end

      options = container.map do |element|
        html_attributes = option_html_attributes(element)
        text, value = option_text_and_value(element).map(&:to_s)

        html_attributes[:selected] = option_value_selected?(value, selected)
        html_attributes[:disabled] = disabled && option_value_selected?(value, disabled)

        ElementsOption.new(text, value, html_attributes)
      end

      ElementsOptionCollection.new(options)
    end

    # Returns structured option data from a collection.
    # Same API as Rails' options_from_collection_for_select.
    #
    #   elements_options_from_collection_for_select(Person.all, :id, :name)
    #   elements_options_from_collection_for_select(Person.all, :id, :name, @person.id)
    #
    def elements_options_from_collection_for_select(collection, value_method, text_method, selected = nil)
      options = collection.map do |element|
        [ value_for_collection(element, text_method), value_for_collection(element, value_method), option_html_attributes(element) ]
      end

      selected, disabled = extract_selected_and_disabled(selected)
      select_deselect = {
        selected: extract_values_from_collection(collection, value_method, selected),
        disabled: extract_values_from_collection(collection, value_method, disabled)
      }

      elements_options_for_select(options, select_deselect)
    end

    # Returns grouped structured option data for use with elements_select_tag.
    # Same API as Rails' grouped_options_for_select.
    #
    #   elements_grouped_options_for_select([
    #     ["Engineering", [["Wade", 1], ["Tom", 2]]],
    #     ["Design", [["Devon", 3], ["Tanya", 4]]]
    #   ])
    #
    #   elements_grouped_options_for_select([
    #     ["Engineering", [["Wade", 1], ["Tom", 2]]],
    #     ["Design", [["Devon", 3], ["Tanya", 4]]]
    #   ], 1)
    #
    def elements_grouped_options_for_select(grouped_options, selected = nil, options = {})
      groups = grouped_options.map do |group|
        label, choices = if group.is_a?(Array)
          [ group[0], group[1] ]
        else
          [ group.first, group.last ]
        end

        ElementsOptionGroup.new(
          label.to_s,
          elements_options_for_select(choices, selected)
        )
      end

      ElementsGroupedOptionCollection.new(groups)
    end

    # Renders an Elements::SelectComponent as a standalone tag helper.
    #
    #   elements_select_tag "person", elements_options_for_select([["Wade", 1], ["Tom", 2]], 1)
    #   elements_select_tag "person", [["Wade", 1], ["Tom", 2]], value: "1"
    #   elements_select_tag("person", value: "1") { |s| s.button { ... } + s.menu { ... } }
    #
    def elements_select_tag(name, choices = nil, options = {}, &block)
      # If choices is a hash, it's actually options (no choices provided)
      if choices.is_a?(Hash)
        options = choices
        choices = nil
      end

      options[:name] = name
      options[:id] ||= sanitize_to_id(name)
      variant = options.delete(:variant) || :default

      if choices.present? && block.nil?
        render Elements::SelectComponent.new(variant: variant, **options) do |select|
          safe_join([
            select.button { |b|
              safe_join([
                b.selected_content,
                icon("chevron-up-down", variant: :mini, class: yass(select: { variant => :icon }))
              ])
            },
            select.menu {
              render_choices(select, choices)
            }
          ])
        end
      else
        render Elements::SelectComponent.new(variant: variant, **options), &block
      end
    end

    # Renders an Elements::ToggleComponent as a standalone tag helper.
    #
    #   toggle_tag "active", checked: true
    #   toggle_tag "active", style: :short
    #   toggle_tag("active") { |t| t.off_icon { icon("x-mark") } + t.on_icon { icon("check") } }
    #
    def toggle_tag(name, options = {}, &block)
      style = options.delete(:style) || :simple

      render Elements::ToggleComponent.new(name, style: style, **options), &block
    end

    # Renders an Elements::AutocompleteComponent as a standalone tag helper.
    #
    #   elements_autocomplete_tag "person", elements_options_for_select(["Wade", "Tom"])
    #   elements_autocomplete_tag "person", ["Wade", "Tom"]
    #   elements_autocomplete_tag("person") { |ac| ... }
    #
    def elements_autocomplete_tag(name, choices = nil, options = {}, &block)
      if choices.is_a?(Hash)
        options = choices
        choices = nil
      end

      create = options.delete(:create) || false
      create_text = options.delete(:create_text)
      settings = options.delete(:settings) || {}
      events = options.delete(:events)
      options.delete(:anchor)
      options.delete(:strict)
      selected_value = options.delete(:value)
      multiple = options[:multiple]
      options[:name] = multiple ? multiple_field_name(name) : name
      options[:id] ||= sanitize_to_id(name)

      if choices.present? && block.nil?
        choice_data = case choices
        when ElementsOptionCollection, ElementsGroupedOptionCollection
          choices
        else
          elements_options_for_select(choices)
        end

        render Elements::AutocompleteComponent.new(create: create, create_text: create_text, settings: settings, events: events, **options) do |ac|
          ac.menu {
            render_choices(ac, choice_data, selected_value)
          }
        end
      else
        render Elements::AutocompleteComponent.new(create: create, create_text: create_text, settings: settings, events: events, **options), &block
      end
    end

    # Finds the display text for a selected value within flat or grouped option collections.
    def resolve_display_text(choices, value)
      return nil if value.blank?

      all_options = case choices
      when ElementsGroupedOptionCollection
        choices.flat_map(&:options)
      when ElementsOptionCollection
        choices.to_a
      else
        return nil
      end

      match = all_options.find { |opt| opt.value.to_s == value.to_s }
      match&.text
    end

    private

    def sanitize_to_id(name)
      name.to_s.delete("]").tr("[]", "_")
    end

    def multiple_field_name(name)
      name.to_s.end_with?("[]") ? name : "#{name}[]"
    end

    public

    def render_choices(select, choices, selected = nil)
      case choices
      when ElementsGroupedOptionCollection
        safe_join(choices.map { |group|
          select.group(group.label) {
            safe_join(group.options.map { |opt|
              select.option(value: opt.value, display: opt.text, disabled: opt.disabled?, selected: option_selected_for_render?(opt, selected))
            })
          }
        })
      when ElementsOptionCollection
        safe_join(choices.map { |opt|
          select.option(value: opt.value, display: opt.text, disabled: opt.disabled?, selected: option_selected_for_render?(opt, selected))
        })
      else
        choice_data = elements_options_for_select(choices)
        safe_join(choice_data.map { |opt|
          select.option(value: opt.value, display: opt.text, disabled: opt.disabled?, selected: option_selected_for_render?(opt, selected))
        })
      end
    end

    def option_selected_for_render?(option, selected)
      return option.selected? if selected.nil?

      Array(selected).map(&:to_s).include?(option.value.to_s)
    end
  end

  # Structured option data — replaces HTML string output
  class ElementsOption
    attr_reader :text, :value, :html_attributes

    def initialize(text, value, html_attributes = {})
      @text = text
      @value = value
      @html_attributes = html_attributes
    end

    def selected?
      !!@html_attributes[:selected]
    end

    def disabled?
      !!@html_attributes[:disabled]
    end
  end

  # A group of options with a label
  class ElementsOptionGroup
    attr_reader :label, :options

    def initialize(label, options)
      @label = label
      @options = options
    end
  end

  # Grouped collection wrapper
  class ElementsGroupedOptionCollection
    include Enumerable

    def initialize(groups)
      @groups = groups
    end

    def each(&block)
      @groups.each(&block)
    end

    def present?
      @groups.any?
    end
  end

  # Collection wrapper so we can detect pre-processed options
  class ElementsOptionCollection
    include Enumerable

    def initialize(options)
      @options = options
    end

    def each(&block)
      @options.each(&block)
    end

    def to_ary
      @options.to_a
    end

    def present?
      @options.any?
    end
  end
end
