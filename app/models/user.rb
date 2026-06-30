class User < ApplicationRecord
  ROLES = %w[admin user].freeze

  validates :name, :email, :role, presence: true
  validates :email, uniqueness: true
  validates :role, inclusion: { in: ROLES }
  validates :password_digest, :password_salt, presence: true
  validates :admin_mobile, format: { with: /\A\d{10,15}\z/, message: "must be 10 to 15 digits" }, allow_blank: true

  has_many :documents, foreign_key: :uploaded_by_id, dependent: :restrict_with_error
  has_many :download_requests, dependent: :destroy

  before_validation :normalize_email, :normalize_admin_mobile

  def admin?
    role == "admin"
  end

  def user?
    role == "user"
  end

  def password=(value)
    return if value.blank?

    self.password_salt = SecureRandom.hex(16)
    self.password_digest = self.class.digest_password(value, password_salt)
  end

  def authenticate(password)
    return false if password.blank? || password_salt.blank? || password_digest.blank?

    expected = self.class.digest_password(password, password_salt)
    ActiveSupport::SecurityUtils.secure_compare(expected, password_digest) && self
  end

  def self.digest_password(password, salt)
    OpenSSL::HMAC.hexdigest("SHA256", salt, password)
  end

  def self.admin_otp_mobile
    where(role: "admin").where.not(admin_mobile: [nil, ""]).order(:id).pick(:admin_mobile)
  end

  private

  def normalize_email
    self.email = email.to_s.strip.downcase
  end

  def normalize_admin_mobile
    self.admin_mobile = admin_mobile.to_s.gsub(/\D/, "").presence
  end
end
