require "json"
require "net/http"

class SmsOtpService
  class DeliveryError < StandardError; end

  BASE_URL = "https://sms.yoursmsbox.com/api/sendhttp.php"
  AUTH_KEY = "3230666f72736131353261"
  SENDER = "ACTFSA"
  ROUTE = "2"
  COUNTRY = "0"
  UNICODE = "1"
  TEMPLATE_ID = "1707174348305252031"
  REFERENCE_NUMBER = "11-1T0PLM8Y0SL49"
  MESSAGE_TEMPLATE = "Action For Social Advancement (ASA)-Login OTP: %<otp>s"

  def self.configured?
    User.admin_otp_mobile.present?
  end

  def self.deliver!(mobile:, otp:)
    new(mobile: mobile, otp: otp).deliver!
  end

  def initialize(mobile:, otp:)
    @mobile = mobile.to_s.strip
    @otp = otp.to_s.strip
  end

  def deliver!
    raise DeliveryError, "Admin OTP mobile number is missing" if @mobile.blank?
    raise DeliveryError, "Invalid mobile number format" unless valid_mobile?

    response = Net::HTTP.get_response(request_uri)
    raise DeliveryError, "SMS API HTTP error #{response.code}" unless response.is_a?(Net::HTTPSuccess)

    parse_response(response.body.to_s)
  rescue JSON::ParserError => error
    raise DeliveryError, "SMS API JSON parse error: #{error.message}"
  rescue StandardError => error
    raise error if error.is_a?(DeliveryError)

    raise DeliveryError, error.message
  end

  private

  def request_uri
    uri = URI(BASE_URL)
    uri.query = URI.encode_www_form(
      authkey: AUTH_KEY,
      mobiles: clean_mobile,
      message: message,
      sender: SENDER,
      route: ROUTE,
      country: COUNTRY,
      DLT_TE_ID: TEMPLATE_ID,
      unicode: UNICODE
    )
    uri
  end

  def parse_response(response_body)
    body = response_body.strip
    Rails.logger.info "SMS API Response: #{body}"

    return true if body.match?(/\A\d+\z/) || body.downcase.include?("success")

    parsed = parse_json_body(body)
    return true if successful_json_response?(parsed)

    raise DeliveryError, sms_error_message(body, parsed)
  end

  def parse_json_body(body)
    return unless body.start_with?("{") && body.end_with?("}")

    JSON.parse(body)
  end

  def successful_json_response?(parsed)
    return false unless parsed.is_a?(Hash)

    status = parsed["Status"].to_s
    code = parsed["Code"].to_s

    status.casecmp("Success").zero? && code.present? && code != "0"
  end

  def sms_error_message(body, parsed)
    return "SMS API error: #{body}" unless parsed.is_a?(Hash)

    description = parsed["Description"].presence || parsed["Status"].presence || body
    "SMS API error: #{description}"
  end

  def valid_mobile?
    return true if clean_mobile.length == 10 && clean_mobile.match?(/\A[6-9]\d{9}\z/)
    return true if clean_mobile.length == 12 && clean_mobile.start_with?("91") && clean_mobile[2..].match?(/\A[6-9]\d{9}\z/)

    false
  end

  def clean_mobile
    @clean_mobile ||= @mobile.gsub(/[^\d+]/, "").delete_prefix("+")
  end

  def message
    format(MESSAGE_TEMPLATE, otp: @otp)
  end
end
