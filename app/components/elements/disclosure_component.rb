module Elements
  class DisclosureComponent < ApplicationComponent
    attr_reader :id

    def initialize(id: nil, hidden: true)
      @id = id || "disclosure-#{SecureRandom.hex(4)}"
      @hidden = hidden
    end

    def call
      content
    end

    def button(text = nil, **options, &block)
      options[:command] = "--toggle"
      options[:commandfor] = @id
      render Elements::ButtonComponent.new(text, unstyled: true, **options, &block)
    end

    def panel(**options, &block)
      panel_content = capture(&block)
      options[:class] = class_names("contents", options[:class])
      tag.el_disclosure(panel_content, id: @id, hidden: @hidden || nil, **options)
    end
  end
end
