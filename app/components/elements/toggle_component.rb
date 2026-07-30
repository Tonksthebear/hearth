module Elements
  class ToggleComponent < ApplicationComponent
    self.yaml_root = :toggle

    def initialize(name, style: :simple, **options)
      @name = name
      @style = style
      @options = options
    end

    def off_icon(&block)
      tag.span(aria: { hidden: true }, class: yass({ icon: :off })) { capture(&block) }
    end

    def on_icon(&block)
      tag.span(aria: { hidden: true }, class: yass({ icon: :on })) { capture(&block) }
    end

    def call
      tag.div(class: yass({ @style => :container })) do
        parts = []
        parts << tag.span(class: yass({ @style => :track })) if @style == :short
        dot_classes = yass({ @style => :dot })
        if content.present?
          dot_classes = class_names(dot_classes, "relative")
          parts << tag.span(class: dot_classes) { content }
        else
          parts << tag.span(class: dot_classes)
        end
        @options[:class] = class_names(yass(:input), @options[:class])
        parts << check_box_tag(@name, **@options)
        safe_join(parts)
      end
    end
  end
end
