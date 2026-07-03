class SessionsController < ApplicationController
  def new
    redirect_to root_path if current_user
  end

  def create
    user = User.find_by(email: params[:email].to_s.downcase.strip)

    if user&.authenticate(params[:password])
      session[:user_id] = user.id
      redirect_to root_path, notice: "Welcome back, #{user.name}."
    else
      flash.now[:alert] = "Invalid email or password."
      render :new, status: :unprocessable_entity
    end
  end

  def ess_login
    employee_code = ess_employee_code

    unless valid_ess_signature?(employee_code)
      redirect_to login_path, alert: "ESS login is not authorized."
      return
    end

    user = User.find_by(employee_code: employee_code)

    if user
      session[:user_id] = user.id
      redirect_to root_path, notice: "Welcome, #{user.name}."
    else
      redirect_to login_path, alert: "Employee is not available in Document Portal."
    end
  end

  def destroy
    reset_session
    redirect_to login_path, notice: "Logged out successfully."
  end

  private

  def ess_employee_code
    params[:employee_code].presence || params[:emp_code].presence
  end

  def valid_ess_signature?(employee_code)
    return false if employee_code.blank?

    signature = params[:signature].to_s
    expires_at = params[:expires_at].to_i
    return valid_legacy_ess_secret? if signature.blank? || expires_at.zero?
    return false if Time.current.to_i > expires_at

    secret = ENV["ESS_LOGIN_SECRET"].to_s
    return false if secret.blank?

    expected_signature = OpenSSL::HMAC.hexdigest("sha256", secret, "#{employee_code}:#{expires_at}")
    secure_compare(signature, expected_signature)
  end

  def valid_legacy_ess_secret?
    expected = ENV["ESS_LOGIN_SECRET"].to_s
    return true if expected.blank?

    secure_compare(params[:secret].to_s, expected)
  end

  def secure_compare(value, expected)
    value.bytesize == expected.bytesize &&
      ActiveSupport::SecurityUtils.secure_compare(value, expected)
  end
end
