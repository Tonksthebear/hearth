module Elements
  class SidebarComponent < ApplicationComponent
    self.yaml_root = :sidebar

    renders_one :sidebar
    renders_one :desktop_sidebar
    renders_one :mobile_sidebar

    renders_one :header, ->(**options, &block) do
      @header_classes = options[:class] || "bg-white dark:border-white/5 dark:bg-gray-900 lg:flex"
      @header_content = block&.call
    end

    renders_one :mobile_menu_button, ->(**options, &block) do
      @mobile_menu_classes = options[:class]|| "text-gray-600 dark:text-white"
      @mobile_menu_content = block&.call
    end

    attr_reader :options, :header_classes, :mobile_menu_classes, :mobile_menu_content

    def initialize(**options)
      case options[:class]
      when Hash
        options[:class][:add] = "#{options[:class][:add]} lg:pl-(--sidebar-width)"
      when String
        options[:class] = class_names("lg:pl-(--sidebar-width)", options[:class])
      else
        options[:class] = "lg:pl-(--sidebar-width)"
      end
      @options = options
    end

    # Sidecar template: mobile_component.html.erb renders the mobile dialog.
    # yaml_root shares sidebar: YAML keys for dialog/backdrop/container/panel styling.
    class MobileComponent < ApplicationComponent
      self.yaml_root = :sidebar
    end

    # Empty class required for ViewComponent's sidecar template lookup.
    # Template: desktop_component.html.erb contains the fixed sidebar markup.
    class DesktopComponent < ApplicationComponent
    end
  end
end
