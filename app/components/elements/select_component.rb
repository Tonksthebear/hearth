module Elements
  class SelectComponent < ApplicationComponent
    self.yaml_root = :select

    attr_reader :options, :variant, :anchor

    def initialize(variant: :default, prompt: nil, anchor: "bottom start", include_blank: nil, **options)
      @prompt = prompt
      @variant = variant
      @options = options
      @anchor = anchor
      @include_blank = include_blank
      @required = options[:required]
    end

    def call
      @options[:class] = class_names(yass(:container), @options[:class])
      content_tag "el-select", content, **options
    end

    # ── Helpers ──

    def button(unstyled: false, **options, &block)
      builder = ButtonBuilder.new(self)
      btn_content = capture(builder, &block)
      options[:class] = class_names(yass({ @variant => :button }), options[:class]) unless unstyled
      options[:type] = :button
      options[:command] ||= "show-popover"
      options[:commandfor] ||= options_id
      render(Elements::ButtonComponent.new(unstyled: true, **options)) { btn_content }
    end

    def menu(unstyled: false, **options, &block)
      menu_content = capture(&block)

      blank = determine_blank_text
      if blank
        menu_content = option(value: "", display: blank) + menu_content
      end

      unless unstyled
        options[:class] = class_names(yass({ @variant => :menu }), anchor_to_origin_class(@anchor), options[:class])
      end
      options[:id] ||= options_id
      tag.el_options(menu_content, anchor: @anchor, popover: "auto", **options)
    end

    def selected_content(prompt = nil, **options, &block)
      options[:class] = class_names(yass({ @variant => :selected }), options[:class])
      if block
        sc_content = capture(&block)
        tag.el_selectedcontent(**options) { sc_content }
      else
        prompt ||= @prompt || "Choose one"
        options[:class] = class_names("truncate", options[:class])
        tag.el_selectedcontent(prompt, **options)
      end
    end

    def group(label, **options, &block)
      group_id = "group-#{label.parameterize}"
      group_content = capture(&block)
      options[:role] = "group"
      options[:"aria-labelledby"] = group_id

      tag.div(**options) do
        safe_join([
          tag.div(label, id: group_id, class: yass(:group)),
          group_content
        ])
      end
    end

    def option(value:, display: nil, unstyled: false, **options, &block)
      if block
        builder = OptionBuilder.new(self)
        opt_content = capture(builder, &block)
      else
        label_text = display || value
        opt_content = tag.span(label_text, class: yass({ @variant => { option: :label } }))
      end

      options[:class] = class_names(yass({ @variant => { option: :container } }), options[:class]) unless unstyled
      tag.el_option(opt_content, value: value, **options)
    end

    # ── Builders ──

    class ButtonBuilder < Builder
      def selected_content(prompt = nil, **options, &block)
        options[:class] = class_names(yass({ @c.variant => :selected }), options[:class])
        if block
          sc_content = capture(&block)
          tag.el_selectedcontent(**options) { sc_content }
        else
          prompt ||= @c.instance_variable_get(:@prompt) || "Choose one"
          options[:class] = class_names("truncate", options[:class])
          tag.el_selectedcontent(prompt, **options)
        end
      end
    end

    class OptionBuilder < Builder
      def label(text = nil, **options, &block)
        options[:class] = class_names(yass({ @c.variant => { option: :label } }), options[:class])
        if block
          label_content = capture(&block)
          tag.span(**options) { label_content }
        else
          tag.span(text, **options)
        end
      end

      def check(**options, &block)
        check_content = capture(&block)
        options[:class] = class_names(yass({ @c.variant => { option: :check } }), options[:class])
        tag.span(**options) { check_content }
      end
    end

    private

    def determine_blank_text
      if @required && @include_blank == false
        raise ArgumentError, "include_blank cannot be false for a required field"
      end

      if @include_blank
        return @include_blank == true ? "" : @include_blank
      end

      if @prompt && value_blank?
        return @prompt == true ? "Please select" : @prompt
      end

      if @required
        return ""
      end

      nil
    end

    def value_blank?
      @options[:value].blank?
    end

    def options_id
      "#{@options[:id]}_options"
    end
  end
end
