class Agent::Grant::Credential
  attr_reader :grant, :bearer

  def initialize(grant:, bearer:)
    @grant = grant
    @bearer = bearer
  end

  def inspect = "#<#{self.class.name} [REDACTED]>"
  alias_method :to_s, :inspect

  def as_json(*) = raise(TypeError, "Agent grant credentials cannot be serialized")
  def encode_with(*) = raise(TypeError, "Agent grant credentials cannot be serialized")
end
