module Elements
  class AutocompleteComponent < ApplicationComponent
    self.yaml_root = :autocomplete

    attr_reader :options

    def initialize(create: false, create_text: nil, settings: {}, events: nil, **options)
      @create = create
      @create_text = create_text || 'Add "{value}"'
      @settings = settings
      @events = events
      @placeholder = options.delete(:placeholder)
      @slim_select_class = options.delete(:class)
      options.delete(:anchor)
      options.delete(:strict)
      @options = options
    end

    def call
      @options[:data] = (@options[:data] || {}).merge(
        elements_autocomplete: true,
        slim_select_options: slim_select_options.to_json
      )
      @options[:data][:slim_select_create] = true if @create
      @options[:data][:slim_select_events] = @events if @events.present?
      content_tag "select", content, **options
    end

    # ── Helpers ──

    def menu(**, &block)
      capture(&block)
    end

    def group(label, **options, &block)
      group_content = capture(&block)
      tag.optgroup(group_content, label: label, **options)
    end

    def option(value:, display: nil, disabled: false, selected: false, **options, &block)
      if block
        builder = OptionBuilder.new(self)
        opt_content = capture(builder, &block)
      else
        opt_content = display || value
      end

      tag.option(opt_content, value: value, disabled: disabled || nil, selected: selected || nil, **options)
    end

    # ── Builders ──

    class OptionBuilder < Builder
      def label(text, **options)
        options[:class] = class_names(yass(option: :label), options[:class])
        tag.span(text, **options)
      end

      def secondary(text, **options)
        options[:class] = class_names(yass(option: :secondary), options[:class])
        tag.span(text, **options)
      end

      def icon(**options, &block)
        icon_content = capture(&block)
        options[:class] = class_names("size-6 shrink-0", options[:class])
        tag.span(**options) { icon_content }
      end
    end

    private

    def slim_select_options
      defaults = {
        settings: {
          addableText: @create_text,
          placeholderText: @placeholder || "Select value"
        }
      }

      config = deep_merge(defaults, settings: @settings)
      config[:cssClasses] = slim_select_classes if slim_select_classes.present?
      config
    end

    def slim_select_classes
      case @slim_select_class
      when Hash
        @slim_select_class
      when nil
        {}
      else
        { main: class_names(@slim_select_class) }
      end
    end

    def deep_merge(left, right)
      left.merge(right) do |_key, left_value, right_value|
        left_value.is_a?(Hash) && right_value.is_a?(Hash) ? deep_merge(left_value, right_value) : right_value
      end
    end
  end
end
