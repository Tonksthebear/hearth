module Elements
  class DropdownComponent < ApplicationComponent
    self.yaml_root = :dropdown

    attr_reader :options

    def initialize(anchor: "bottom end", **options)
      @anchor = anchor
      @options = options
    end

    def call
      @options[:class] = class_names(yass(:container), @options[:class])
      content_tag "el-dropdown", content, **options
    end

    def button(text = nil, **options, &block)
      render Elements::ButtonComponent.new(text, unstyled: true, **options, &block)
    end

    def menu(**options, &block)
      menu_content = capture(&block)
      options[:class] = class_names(yass(:menu), anchor_to_origin_class(@anchor), options[:class])
      tag.el_menu(menu_content, anchor: @anchor, popover: "auto", **options)
    end

    def section(**options, &block)
      section_content = capture(&block)
      options[:class] = class_names(yass(:section), options[:class])
      tag.div(section_content, **options)
    end

    def item(text = nil, **options, &block)
      options[:class] = class_names(yass(item: :container), options[:class])
      if block
        item_builder = ItemBuilder.new(self)
        item_content = capture(item_builder, &block)
        render(Elements::ButtonComponent.new(unstyled: true, **options)) { item_content }
      else
        render Elements::ButtonComponent.new(text, unstyled: true, **options)
      end
    end

    class ItemBuilder < Builder
      def icon(**options, &block)
        icon_content = capture(&block)
        options[:class] = class_names(yass(item: :icon), options[:class])
        tag.span(**options) { icon_content }
      end
    end
  end
end
