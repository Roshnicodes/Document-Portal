class DownloadRequest < ApplicationRecord
  OTP_TTL = 10.minutes

  belongs_to :document, optional: true
  belongs_to :user

  validates :otp_digest, :expires_at, presence: true
  validate :target_present

  scope :latest_first, -> { order(created_at: :desc) }

  attr_reader :plain_otp

  def self.create_with_otp!(document:, user:)
    otp = SecureRandom.random_number(100_000..999_999).to_s
    create!(
      document: document,
      user: user,
      otp_digest: digest_otp(otp),
      expires_at: OTP_TTL.from_now
    ).tap { |request| request.instance_variable_set(:@plain_otp, otp) }
  end

  def self.create_folder_with_otp!(folder_key:, folder_name:, user:)
    otp = SecureRandom.random_number(100_000..999_999).to_s
    create!(
      folder_key: folder_key,
      folder_name: folder_name,
      user: user,
      otp_digest: digest_otp(otp),
      expires_at: OTP_TTL.from_now
    ).tap { |request| request.instance_variable_set(:@plain_otp, otp) }
  end

  def target_name
    document&.title || folder_name || folder_key || "GIS folder"
  end

  def target_path
    document&.display_path || folder_key || target_name
  end

  def status_label
    return "Downloaded" if downloaded_at.present?
    return "Verified" if verified?
    return "Expired" if expired?

    "Waiting"
  end

  def verify!(otp)
    return false if expired? || verified?

    return false unless ActiveSupport::SecurityUtils.secure_compare(self.class.digest_otp(otp.to_s.strip), otp_digest)

    update!(verified_at: Time.current)
  end

  def expired?
    expires_at.past?
  end

  def verified?
    verified_at.present?
  end

  def mark_downloaded!
    update!(downloaded_at: Time.current)
  end

  def self.digest_otp(otp)
    OpenSSL::Digest::SHA256.hexdigest(otp)
  end

  private

  def target_present
    return if document.present? || folder_key.present?

    errors.add(:base, "Document or folder is required")
  end
end
