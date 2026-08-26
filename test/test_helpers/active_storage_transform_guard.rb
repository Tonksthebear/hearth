module ActiveStorageTransformGuard
  module Methods
    %i[variant preview representation].each do |method_name|
      define_method(method_name) do |*arguments, **keywords, &block|
        forbidden = Thread.current[:forbidden_active_storage_transforms]
        if forbidden&.include?(method_name)
          raise "#{self.class.name}##{method_name} must not be called"
        end

        super(*arguments, **keywords, &block)
      end
    end
  end

  def with_forbidden_active_storage_transforms(*method_names)
    previous = Thread.current[:forbidden_active_storage_transforms]
    Thread.current[:forbidden_active_storage_transforms] = method_names.map(&:to_sym)
    yield
  ensure
    Thread.current[:forbidden_active_storage_transforms] = previous
  end
end

ActiveStorage::Attachment.prepend(ActiveStorageTransformGuard::Methods)
ActiveStorage::Blob.prepend(ActiveStorageTransformGuard::Methods)
