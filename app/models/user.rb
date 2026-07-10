class User < ApplicationRecord
  ROLES = %w[admin user].freeze
  ADMIN_EMPLOYEE_CODE = "397".freeze

  validates :name, :email, :role, presence: true
  validates :email, uniqueness: true
  validates :employee_code, uniqueness: true, allow_blank: true
  validates :role, inclusion: { in: ROLES }
  validates :password_digest, :password_salt, presence: true
  validates :admin_mobile, format: { with: /\A\d{10,15}\z/, message: "must be 10 to 15 digits" }, allow_blank: true

  has_many :documents, foreign_key: :uploaded_by_id, dependent: :restrict_with_error
  has_many :download_requests, dependent: :destroy

  before_validation :normalize_email, :normalize_admin_mobile, :normalize_employee_details, :apply_admin_employee_code_role

  def effective_role
    employee_code == ADMIN_EMPLOYEE_CODE ? "admin" : "user"
  end

  def admin?
    effective_role == "admin"
  end

  def user?
    effective_role == "user"
  end

  def ensure_canonical_role!
    canonical_role = effective_role
    return if role == canonical_role

    persisted? ? update_column(:role, canonical_role) : self.role = canonical_role
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
    where(employee_code: ADMIN_EMPLOYEE_CODE).where.not(admin_mobile: [nil, ""]).pick(:admin_mobile)
  end

  def location_scope_name
    source = office_name.presence || office_type
    self.class.location_name_from(source)
  end

  def location_restricted?
    user? && location_scope_name.present?
  end

  def self.location_name_from(value)
    value.to_s
      .sub(/\A\s*(to|fco)\s*[-:]\s*/i, "")
      .sub(/\s*\(.+\)\s*\z/, "")
      .squish
      .presence
  end

  private

  def normalize_email
    self.email = email.to_s.strip.downcase
  end

  def normalize_admin_mobile
    self.admin_mobile = admin_mobile.to_s.gsub(/\D/, "").presence
  end

  def normalize_employee_details
    self.employee_code = employee_code.to_s.squish.presence
    self.mobile_number = mobile_number.to_s.gsub(/\D/, "").presence
    self.l1_code = l1_code.to_s.squish.presence
    self.l1_name = l1_name.to_s.squish.presence
    self.l2_code = l2_code.to_s.squish.presence
    self.l2_name = l2_name.to_s.squish.presence
    self.l3_code = l3_code.to_s.squish.presence
    self.l3_name = l3_name.to_s.squish.presence
    self.designation = designation.to_s.squish.presence
    self.position = position.to_s.squish.presence
    self.office_type = office_type.to_s.squish.presence
    self.office_name = office_name.to_s.squish.presence
    self.department = department.to_s.squish.presence
  end

  def apply_admin_employee_code_role
    self.role = effective_role
  end
end
