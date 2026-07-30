module Elements
  class DrawerComponent < DialogComponent
    self.yaml_root = :drawer

    def initialize(id:, open: false, style: :right, backdrop: false, **options)
      super(id: id, open: open, style: style)
      @backdrop = backdrop
      @panel_class = options[:class]
    end

    def backdrop?
      @backdrop
    end
  end
end
