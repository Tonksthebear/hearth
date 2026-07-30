module Elements
  class CommandPaletteComponent < ApplicationComponent
    self.yaml_root = :command_palette

    attr_reader :options, :shape

    def initialize(shape: :rounded, **options)
      @shape = shape
      @options = options
    end

    def call
      content_tag "el-command-palette", content, **options
    end

    # ── Helpers ──

    def list(&block)
      list_builder = ListBuilder.new(self)
      list_content = capture(list_builder, &block)
      tag.el_command_list(list_content, class: yass(:list))
    end

    def no_results(&block)
      builder = NoResultsBuilder.new(self)
      nr_content = capture(builder, &block)
      tag.el_no_results(nr_content, hidden: true, class: yass(no_results: :container))
    end

    # ── Builders ──

    class ListBuilder < Builder
      def defaults(**options, &block)
        defaults_content = capture(self, &block)
        options[:class] = class_names(yass(:defaults), options[:class])
        tag.el_defaults(defaults_content, **options)
      end

      def group(title = nil, **options, &block)
        group_builder = GroupBuilder.new(@c)
        group_content = capture(group_builder, &block)
        options[:class] = class_names(yass(group: :base), options[:class])

        tag.el_command_group(hidden: true, **options) do
          parts = []
          parts << tag.div(title, class: yass(group: :heading)) if title
          parts << tag.div(group_content, class: yass(group: :items))
          safe_join(parts)
        end
      end

      def section(title = nil, **options, &block)
        section_builder = SectionBuilder.new(@c)
        section_content = capture(section_builder, &block)
        options[:class] = class_names(yass(section: :base), options[:class])

        tag.div(**options) do
          parts = []
          parts << tag.h2(title, class: yass(section: :heading)) if title
          parts << tag.div(section_content, class: yass(section: :text))
          safe_join(parts)
        end
      end

      def item(text = nil, hidden: true, **options, &block)
        render_item(text, hidden: hidden, **options, &block)
      end

      private

      def render_item(text, hidden:, **options, &block)
        options[:class] = class_names(yass(item: { container: @c.shape }), options[:class])
        options[:hidden] = hidden

        if block
          item_builder = ItemBuilder.new(@c)
          item_content = capture(item_builder, &block)
          render(Elements::ButtonComponent.new(unstyled: true, **options)) { item_content }
        else
          render Elements::ButtonComponent.new(text, unstyled: true, **options)
        end
      end
    end

    class SectionBuilder < ListBuilder
      def item(text = nil, hidden: false, **options, &block)
        render_item(text, hidden: hidden, **options, &block)
      end
    end

    class GroupBuilder < ListBuilder
      def item(text = nil, hidden: true, **options, &block)
        render_item(text, hidden: hidden, **options, &block)
      end
    end

    class ItemBuilder < Builder
      def icon(**options, &block)
        icon_content = capture(&block)
        options[:class] = class_names(yass(item: :icon), options[:class])
        tag.span(**options) { icon_content }
      end

      def label(text, **options)
        options[:class] = class_names(yass(item: :label), options[:class])
        tag.span(text, **options)
      end

      def hint(text, **options)
        options[:class] = class_names(yass(item: :hint), options[:class])
        tag.span(text, aria: { hidden: true }, **options)
      end

      def shortcut(text, **options)
        options[:class] = class_names(yass(item: :shortcut), options[:class])
        tag.span(aria: { hidden: true }, **options) do
          text.chars.map { |key| tag.kbd(key, class: "font-sans") }.join.html_safe
        end
      end
    end

    class NoResultsBuilder < Builder
      def icon(**options, &block)
        icon_content = capture(&block)
        options[:class] = class_names(yass(no_results: :icon), options[:class])
        tag.span(**options) { icon_content }
      end

      def title(text, **options)
        options[:class] = class_names(yass(no_results: :title), options[:class])
        tag.p(text, **options)
      end

      def description(text, **options)
        options[:class] = class_names(yass(no_results: :text), options[:class])
        tag.p(text, **options)
      end
    end
  end
end
