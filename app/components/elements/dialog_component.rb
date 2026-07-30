module Elements
  class DialogComponent < ApplicationComponent
    self.yaml_root = :dialog

    attr_reader :id, :open, :style, :size, :scrollable

    def initialize(id:, open: false, style: :centered, size: :default, scrollable: false)
      @id = id
      @open = open
      @style = style
      @size = size
      @scrollable = scrollable
    end

    def title(text, **options)
      options[:id] = "dialog-title"
      options[:class] = class_names(yass(:title), options[:class])
      tag.h3(text, **options)
    end

    def description(text, **options)
      options[:class] = class_names(yass(:description), options[:class])
      tag.p(text, **options)
    end

    def header(**options, &block)
      header_content = capture(&block)
      options[:class] = class_names(yass(:header), options[:class])
      tag.div(header_content, **options)
    end

    def body(**options, &block)
      body_content = capture(&block)
      options[:class] = class_names(yass(:body), options[:class])
      tag.div(body_content, **options)
    end

    def footer(**options, &block)
      footer_content = capture(&block)
      options[:class] = class_names(yass(:footer), options[:class])
      tag.div(footer_content, **options)
    end

    def close_button(text = nil, **options, &block)
      options[:command] = "close"
      options[:commandfor] = @id
      render Elements::ButtonComponent.new(text, **options, &block)
    end

    def dismiss_button(icon_name: "x-mark", **options, &block)
      options[:command] = "close"
      options[:commandfor] = @id
      options[:class] = class_names(yass(:dismiss), options[:class])
      render Elements::ButtonComponent.new(unstyled: true, **options) do
        if block
          capture(&block)
        else
          safe_join([
            tag.span("Close", class: "sr-only"),
            icon(icon_name, variant: :outline, class: "size-6")
          ])
        end
      end
    end
  end
end
