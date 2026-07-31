module Agent::SecretFreeSnapshot
  extend ActiveSupport::Concern

  private
    def contains_secret_key?(value)
      case value
      when Hash
        value.any? do |key, nested|
          key.to_s.match?(/(?:token|secret|password|authorization|credentials?)\z/i) ||
            contains_secret_key?(nested)
        end
      when Array
        value.any? { |nested| contains_secret_key?(nested) }
      else
        false
      end
    end
end
