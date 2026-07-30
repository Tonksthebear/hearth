module Elements
  class ApplicationComponent < ViewComponent::Base
    include Classy::Yaml::Helpers

    class_attribute :yaml_root

    delegate :icon, to: :helpers

    def class_names(*args)
      TailwindMerge::Merger.new.merge(super)
    end

    def yass(path)
      if self.class.yaml_root
        super(self.class.yaml_root => path)
      else
        super
      end
    end

    class Builder
      def initialize(component)
        @c = component
      end

      private

      delegate :tag, :capture, :safe_join, :class_names, :render, :yass, :icon, to: :@c
    end

    private

    def anchor_to_origin_class(anchor)
      case anchor
      when "bottom start" then "origin-top-left"
      when "bottom end"   then "origin-top-right"
      when "bottom"       then "origin-top"
      when "top start"    then "origin-bottom-left"
      when "top end"      then "origin-bottom-right"
      when "top"          then "origin-bottom"
      when "right start"  then "origin-top-left"
      when "right end"    then "origin-bottom-left"
      when "right"        then "origin-left"
      when "left start"   then "origin-top-right"
      when "left end"     then "origin-bottom-right"
      when "left"         then "origin-right"
      end
    end
  end
end
