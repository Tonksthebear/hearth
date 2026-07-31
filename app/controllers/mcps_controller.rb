class McpsController < ActionController::API
  before_action :require_loopback
  before_action :authenticate_grant

  def create
    status, transport_headers, body = HearthMcp::Catalog.transport(grant: @grant).call(request.env)
    self.status = status
    transport_headers.each { |name, value| response.set_header(name, value) }
    response.set_header("Cache-Control", "private, no-store")
    response.set_header("Pragma", "no-cache")
    self.response_body = body
  end

  private
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
