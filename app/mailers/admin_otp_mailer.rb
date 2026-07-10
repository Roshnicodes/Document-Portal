class AdminOtpMailer < ApplicationMailer
  def download_otp
    @download_request = params[:download_request]
    @otp = params[:otp]
    @document = @download_request.document
    @target_name = @download_request.target_name
    @user = @download_request.user

    mail(to: User.where(employee_code: User::ADMIN_EMPLOYEE_CODE).pluck(:email), subject: "Document download OTP: #{@target_name}")
  end
end
