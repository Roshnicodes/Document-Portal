require_dependency Rails.root.join("app/services/sms_otp_service").to_s

class AdminOtpDelivery
  def self.deliver!(download_request:, otp:)
    new(download_request, otp).deliver!
  end

  def initialize(download_request, otp)
    @download_request = download_request
    @otp = otp
  end

  def deliver!
    service = sms_service
    return deliver_email unless service&.configured?

    service.deliver!(mobile: admin_mobile, otp: @otp)
    :sms
  rescue StandardError => error
    Rails.logger.warn("Admin OTP SMS delivery failed, falling back to email: #{error.class} - #{error.message}")
    deliver_email
  end

  private

  def sms_service
    ::SmsOtpService
  rescue NameError
    require_dependency Rails.root.join("app/services/sms_otp_service").to_s
    ::SmsOtpService
  end

  def admin_mobile
    User.admin_otp_mobile.to_s.strip
  end

  def deliver_email
    AdminOtpMailer.with(download_request: @download_request, otp: @otp).download_otp.deliver_now
    :email
  end
end
