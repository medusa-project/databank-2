class SessionsController < ApplicationController
  skip_before_action :authenticate_user!
  skip_before_action :verify_authenticity_token

  # Responds to `GET /login`
  def new
    store_login_return_referer

    unless Rails.env.test? || Rails.env.development?
      redirect_to(shibboleth_login_path(Databank2::Application.shibboleth_host))
      nil
    end
  end

  # Responds to `POST /auth/:provider/callback`
  def create
    auth = request.env["omniauth.auth"]

    unless auth&.[](:provider) && [ "shibboleth", "developer" ].include?(auth[:provider])
      unauthorized
      return
    end

    if auth[:provider] == "developer" && !(Rails.env.test? || Rails.env.development?)
      unauthorized
      return
    end

    user = User.from_omniauth(auth)

    if user&.id
      session[:user_id] = user.id
      if user.role == "no_deposit" && !user.depositor?
        redirect_to root_url, notice: "ACCOUNT NOT ELIGABLE TO DEPOSIT DATA.<br/>Faculty, staff, and graduate students are eligable to deposit data in Illinois Data Bank.<br/>Please <a href='/help'>contact the Research Data Service</a> if this determination is in error, or if you have any questions."
      else
        redirect_to return_url
      end
    else
      redirect_to root_url
    end
  end

  def destroy
    session[:user_id] = nil
    redirect_to root_url
  end

  # Responds to `GET /auth/failure`
  def unauthorized
    redirect_to root_url, notice: "The supplied credentials could not be authenciated."
  end

  # Responds to `POST /role_switch`
  def role_switch
    new_role = params["role"]
    if [ "depositor", "guest", "no_deposit" ].include?(new_role)
      new_role_text = "new role"
      case new_role
      when "depositor"
        current_user.update_attribute(:role, "depositor") # rubocop:disable Rails/SkipsModelValidations
        new_role_text = "depositor"
      when "guest"
        current_user.update_attribute(:role, "guest") # rubocop:disable Rails/SkipsModelValidations
        new_role_text = "guest"
      when "no_deposit"
        current_user.update_attribute(:role, "no_deposit") # rubocop:disable Rails/SkipsModelValidations
        new_role_text = "undergrad, or other authenticated but not authorized agent"
      end
      redirect_to root_url, notice: "Successfully switched role to #{new_role_text}."
    else
      redirect_to root_url, notice: "Unable to switch roles."
    end
  end

  protected

  def return_url
    session.delete(:login_return_uri) || session.delete(:login_return_referer) || root_path
  end

  def shibboleth_login_path(host)
    "/Shibboleth.sso/Login?target=https://#{host}/auth/shibboleth/callback"
  end

  def store_login_return_referer
    return if session[:login_return_uri].present?

    referer = safe_internal_return_path(request.referer)
    session[:login_return_referer] = referer if referer.present?
  end

  def safe_internal_return_path(url)
    return if url.blank?

    uri = URI.parse(url)
    return uri.to_s if uri.host.blank? && uri.path.present? && uri.path != login_path
    return if uri.host.present? && uri.host != request.host
    return if uri.path.blank? || uri.path == login_path

    [ uri.path, uri.query.presence && "?#{uri.query}" ].compact.join
  rescue URI::InvalidURIError
    nil
  end
end
