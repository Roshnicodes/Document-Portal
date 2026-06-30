class Document < ApplicationRecord
  belongs_to :uploaded_by, class_name: "User"
  has_many :download_requests, dependent: :destroy
  has_one_attached :file

  validates :title, presence: true
  validates :file, presence: true

  before_validation :normalize_folder_fields

  def file_name
    file.filename.to_s
  end

  def display_path
    folder_path.presence || file_name
  end

  def folder_label
    folder_name.presence || "Single files"
  end

  def download_folder_key
    return folder_label if folder_path.blank?

    File.dirname(folder_path)
  end

  def download_folder_name
    File.basename(download_folder_key)
  end

  def file_size
    return "0 KB" unless file.attached?

    ActiveSupport::NumberHelper.number_to_human_size(file.byte_size)
  end

  private

  def normalize_folder_fields
    self.folder_name = folder_name.to_s.strip.presence
    self.folder_path = folder_path.to_s.strip.presence
    self.upload_batch_id = upload_batch_id.to_s.strip.presence
  end
end
