module Authentication
  extend ActiveSupport::Concern

  included do
    before_action :require_authentication
    helper_method :authenticated?
  end

  class_methods do
    def allow_unauthenticated_access(**options)
      skip_before_action :require_authentication, **options
    end
  end

  private
    def authenticated?
      resume_session
    end

    def require_authentication
      resume_session || request_authentication
    end

    def resume_session
      Current.session ||= find_session_by_cookie
    end

    def find_session_by_cookie
      Session.find_by(id: cookies.signed[:session_id]) if cookies.signed[:session_id]
    end

    def establish_current_context
      Current.household = Current.user.person.household
      Current.person = Current.household.person_for(session[:person_id], fallback: Current.user.person)
      session[:person_id] = Current.person.id if session[:person_id] != Current.person.id
    end

    def request_authentication
      if Household.configured?
        session[:return_to_after_authenticating] = request.url
        redirect_to new_session_path
      else
        redirect_to new_setup_household_path
      end
    end

    def after_authentication_url
      session.delete(:return_to_after_authenticating) || root_url
    end

    def start_new_session_for(user)
      session.delete(:person_id)
      user.sessions.create!(user_agent: request.user_agent, ip_address: request.remote_ip).tap do |session|
        Current.session = session
        cookies.signed.permanent[:session_id] = { value: session.id, httponly: true, same_site: :lax }
      end
    end

    def terminate_session
      Current.session.destroy
      cookies.delete(:session_id)
      session.delete(:person_id)
    end
end
