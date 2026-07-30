module Elements
  class CopyableComponent < ApplicationComponent
    self.yaml_root = :copyable

    attr_reader :id

    def initialize(id: nil)
      @id = id || "copyable-#{SecureRandom.hex(4)}"
    end

    def source(**options, &block)
      source_content = capture(&block)
      tag.el_copyable(source_content, id: @id, **options)
    end

    def button(text = nil, **options, &block)
      options[:command] = "--copy"
      options[:commandfor] = @id
      render Elements::ButtonComponent.new(text, unstyled: true, **options, &block)
    end

    def copy_icon(**options, &block)
      options[:class] = class_names(yass({ icon: :copy }), options[:class])
      tag.span(**options) { capture(&block) }
    end

    def copied_icon(**options, &block)
      options[:class] = class_names(yass({ icon: :copied }), options[:class])
      tag.span(**options) { capture(&block) }
    end

    def call
      content
    end
  end
end
