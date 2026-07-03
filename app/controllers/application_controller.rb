class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  helper_method :current_user, :admin_user?

  private

  def current_user
    @current_user ||= User.find_by(id: session[:user_id]) if session[:user_id].present?
  end

  def require_login
    return if current_user

    redirect_to ess_login_path, alert: "Please open Document Portal from ESS."
  end

  def require_admin
    return if admin_user?

    redirect_to root_path, alert: "Only admin can access this page."
  end

  def admin_user?
    current_user&.admin?
  end
end
