class ApplicationController < ActionController::Base
  include CanCan::ControllerAdditions

  SESSION_IDLE_TIMEOUT = 8.hours + 30.minutes

  allow_browser versions: :modern
  stale_when_importmap_changes

  before_action :load_system_message
  before_action :expire_session_after_inactivity
  before_action :authenticate_user!
  before_action :mark_session_activity

  helper_method :current_user, :logged_in?, :system_message

  rescue_from CanCan::AccessDenied do |_exception|
    redirect_to root_path, alert: "You are not authorized to perform this action."
  end

  private

  def current_user
    @current_user ||= User.find_by(id: session[:user_id])
  end

  def logged_in?
    current_user.present?
  end

  def authenticate_user!
    return if logged_in?

    session[:login_return_uri] = request.env["REQUEST_URI"]
    redirect_to(login_path, alert: "Please sign in to continue.")
  end

  def expire_session_after_inactivity
    return if session[:user_id].blank?

    last_seen_at = session[:last_seen_at].to_i
    return if last_seen_at <= 0
    return if Time.current.to_i - last_seen_at <= SESSION_IDLE_TIMEOUT

    return_uri = request.env["REQUEST_URI"]
    reset_session
    session[:login_return_uri] = return_uri
    redirect_to(login_path, alert: "Your session has expired. Please sign in again.")
  end

  def mark_session_activity
    return unless logged_in?

    session[:last_seen_at] = Time.current.to_i
  end

  def load_system_message
    @system_message = AppSetting.system_message
  end

  def system_message
    @system_message
  end
end
