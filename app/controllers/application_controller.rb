class ApplicationController < ActionController::Base
  include CanCan::ControllerAdditions

  allow_browser versions: :modern
  stale_when_importmap_changes

  before_action :load_system_message
  before_action :authenticate_user!

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

    redirect_to login_path, alert: "Please sign in to continue."
  end

  def load_system_message
    @system_message = AppSetting.system_message
  end

  def system_message
    @system_message
  end
end
