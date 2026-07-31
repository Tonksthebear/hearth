class McpsController < ActionController::API
  wrap_parameters false

  before_action :require_loopback
  before_action :authenticate_grant

  def show = dispatch_transport
  def create = dispatch_transport
  def destroy = dispatch_transport

  private
    def dispatch_transport
      status, transport_headers, body = HearthMcp::Catalog.transport(grant: @grant).call(request.env)
      self.status = status
      transport_headers.each { |name, value| response.set_header(name, value) }
      response.set_header("Cache-Control", "private, no-store")
      response.set_header("Pragma", "no-cache")
      self.response_body = body
    end

    def require_loopback
      head :forbidden unless request.local?
    end

    def authenticate_grant
      scheme, bearer = request.authorization.to_s.split(" ", 2)
      @grant = Agent::Grant.authenticate(bearer: bearer) if scheme == "Bearer"
      return if @grant

      response.set_header("WWW-Authenticate", 'Bearer realm="hearth-mcp"')
      head :unauthorized
    end
end
