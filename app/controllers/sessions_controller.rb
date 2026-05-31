class SessionsController < ApplicationController
  skip_before_action :authenticate_user!

  def new; end

  def create
    auth = request.env["omniauth.auth"] || shibboleth_auth_from_headers
    unless auth
      redirect_to login_path, alert: "Authentication failed."
      return
    end

    user = User.from_omniauth(auth)
    session[:user_id] = user.id
    redirect_to root_path
  end

  def destroy
    session[:user_id] = nil
    redirect_to root_path, notice: "Signed out."
  end

  # Development-only role switching
  def role_switch
    unless Rails.env.development? || Rails.env.test?
      redirect_back fallback_location: root_path, alert: "Role switching is only available in development and test."
      return
    end

    user = current_user
    if user && params[:role].present?
      user.update!(role: params[:role])
      session[:user_id] = user.id
    end
    redirect_back fallback_location: root_path
  end

  private

  def shibboleth_auth_from_headers
    return nil unless params[:provider] == "shibboleth"

    uid = request.env["HTTP_EPPN"].presence ||
          request.env["REMOTE_USER"].presence ||
          request.env["HTTP_UID"].presence
    email = request.env["HTTP_MAIL"].presence || uid
    name = request.env["HTTP_DISPLAYNAME"].presence ||
           request.env["HTTP_CN"].presence ||
           uid

    return nil if uid.blank? || email.blank?

    OmniAuth::AuthHash.new(
      provider: "shibboleth",
      uid: uid,
      info: {
        email: email,
        name: name,
        nickname: uid
      }
    )
  end
end
