module Elements
  class TabGroupComponent < ApplicationComponent
    self.yaml_root = :tab_group

    attr_reader :options

    def initialize(style: :underline, color: :primary, **options)
      @style = style
      @color = color
      @options = options
    end

    def call
      content_tag "el-tab-group", content, **options
    end

    def tab_list(**options, &block)
      options[:class] = class_names(yass({ @style => :list }), options[:class])
      list_content = capture(&block)
      tag.el_tab_list(list_content, **options)
    end

    def tab_panels(**options, &block)
      panels_content = capture(&block)
      tag.el_tab_panels(panels_content, **options)
    end

    def tab(text = nil, **options, &block)
      options[:class] = class_names(yass({ @style => { tab: [ :base, @color ] } }), options[:class])
      render Elements::ButtonComponent.new(text, unstyled: true, **options, &block)
    end

    def panel(hidden: false, **options, &block)
      options[:class] = class_names(yass(:panel), options[:class])
      options[:hidden] = true if hidden
      tag.div(**options, &block)
    end
  end
end
