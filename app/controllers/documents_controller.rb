require "zip"
require_dependency Rails.root.join("app/services/sms_otp_service").to_s
require Rails.root.join("app/services/admin_otp_delivery").to_s

class DocumentsController < ApplicationController
  before_action :require_login
  before_action :set_document, only: %i[show destroy request_otp verify confirm_otp download]
  before_action :require_admin, only: %i[destroy]

  def index
    documents_scope = visible_documents_scope(Document.includes(:uploaded_by, file_attachment: :blob)).order(created_at: :desc)
    folder_keys = folder_keys_for(documents_scope)
    @folder_max_depth = folder_max_depth(folder_keys)
    @folder_select_labels = folder_select_labels(folder_keys, @folder_max_depth)
    @folder_level_options, @selected_folder_parts = folder_selection_for(folder_keys, @folder_max_depth)
    @folder_selection_params = folder_selection_params(@selected_folder_parts)
    @selected_folder_key = selected_folder_key(@selected_folder_parts, @folder_max_depth)
    @selected_folder_prefix = selected_folder_prefix(@selected_folder_parts)
    @search_query = params[:q].to_s.strip
    @filter_params = filter_params(@folder_selection_params, @search_query)
    @search_performed = @selected_folder_prefix.present? || @search_query.present?
    @documents = @search_performed ? filtered_documents(documents_scope, @selected_folder_prefix, @search_query) : []
    @current_folder = current_folder_for_selection(@selected_folder_key, @selected_folder_prefix, @documents)
    @current_folder = nil if @current_folder == "."
    @folder_items = folder_items_for(@current_folder)
    @breadcrumbs = breadcrumbs_for(@current_folder)
    @total_downloadable_folders = @documents.group_by(&:download_folder_key).count
    @location_scope_name = current_user.location_scope_name unless admin_user?
    @recent_requests = DownloadRequest.includes(:document, :user).latest_first.limit(8) if admin_user?
  end

  def show
  end

  def destroy
    @document.destroy
    redirect_to root_path, notice: "File removed successfully."
  end

  def request_otp
    unless valid_download_purpose?
      redirect_to @document, alert: download_purpose_error_message
      return
    end

    request = DownloadRequest.create_with_otp!(document: @document, user: current_user, download_purpose: download_purpose)
    delivery_channel = deliver_admin_otp(request)

    redirect_to verify_document_path(@document, request_id: request.id), notice: otp_delivery_notice(delivery_channel)
  end

  def request_folder_otp
    unless valid_download_purpose?
      redirect_back fallback_location: root_path, alert: download_purpose_error_message
      return
    end

    folder_key = params[:folder_key].to_s
    documents = documents_for_folder(folder_key)

    if documents.empty?
      redirect_to root_path, alert: "Folder not found."
      return
    end

    request = DownloadRequest.create_folder_with_otp!(
      folder_key: folder_key,
      folder_name: File.basename(folder_key),
      user: current_user,
      download_purpose: download_purpose
    )
    delivery_channel = deliver_admin_otp(request)

    redirect_to verify_folder_documents_path(request_id: request.id), notice: otp_delivery_notice(delivery_channel, folder: true)
  end

  def verify
    @download_request = current_user.download_requests.find_by(id: params[:request_id], document: @document)
    redirect_to root_path, alert: "Download request not found." unless @download_request
  end

  def verify_folder
    @download_request = current_user.download_requests.find_by(id: params[:request_id])
    redirect_to root_path, alert: "Folder download request not found." unless @download_request&.folder_key.present?
  end

  def confirm_otp
    @download_request = current_user.download_requests.find_by(id: params[:request_id], document: @document)

    if @download_request&.verify!(params[:otp])
      redirect_to download_document_path(@document, request_id: @download_request.id), notice: "OTP verified. Download started."
    else
      flash.now[:alert] = "The OTP is invalid or has expired."
      @download_request ||= DownloadRequest.new(document: @document, user: current_user)
      render :verify, status: :unprocessable_entity
    end
  end

  def confirm_folder_otp
    @download_request = current_user.download_requests.find_by(id: params[:request_id])

    if @download_request&.folder_key.present? && @download_request.verify!(params[:otp])
      redirect_to download_folder_documents_path(request_id: @download_request.id), notice: "OTP verified. Folder download started."
    else
      flash.now[:alert] = "The OTP is invalid or has expired."
      @download_request ||= DownloadRequest.new(user: current_user)
      render :verify_folder, status: :unprocessable_entity
    end
  end

  def download
    request = current_user.download_requests.find_by(id: params[:request_id], document: @document)

    unless request&.verified? && !request.expired?
      redirect_to verify_document_path(@document, request_id: request&.id), alert: "A valid OTP is required before downloading."
      return
    end

    request.mark_downloaded!
    redirect_to rails_blob_path(@document.file, disposition: "attachment")
  end

  def download_folder
    request = current_user.download_requests.find_by(id: params[:request_id])

    unless request&.folder_key.present? && request.verified? && !request.expired?
      redirect_to verify_folder_documents_path(request_id: request&.id), alert: "A valid OTP is required before downloading this folder."
      return
    end

    documents = documents_for_folder(request.folder_key)
    if documents.empty?
      redirect_to root_path, alert: "Folder files not found."
      return
    end

    zip_path = build_folder_zip(request.folder_key, documents, request.id)
    request.mark_downloaded!
    send_file zip_path, filename: folder_zip_filename(request.folder_key), type: "application/zip", disposition: "attachment"
  end

  private

  def set_document
    @document = visible_documents_scope(Document).find(params[:id])
  end

  def visible_documents_scope(scope)
    return scope if admin_user?

    location = current_user.location_scope_name
    return scope.none if location.blank?

    safe_location = ActiveRecord::Base.sanitize_sql_like(location)
    scope.where("folder_path = ? OR folder_path LIKE ? OR folder_path LIKE ?", safe_location, "#{safe_location}/%", "%/#{safe_location}/%")
  end

  def download_purpose
    params[:download_purpose].to_s.squish
  end

  def valid_download_purpose?
    download_purpose.split.size >= DownloadRequest::MIN_PURPOSE_WORDS
  end

  def download_purpose_error_message
    "Please enter at least #{DownloadRequest::MIN_PURPOSE_WORDS} words in the purpose of download before requesting OTP."
  end

  def folder_keys_for(scope)
    scope.filter_map do |document|
      folder_key_for(document.folder_path)
    end.uniq
  end

  def folder_max_depth(folder_keys)
    folder_keys.map { |folder_key| folder_key.split("/").size }.max.to_i
  end

  def folder_select_labels(folder_keys, max_depth)
    labels = ["State", "District", "Block", "Village", "Data type"]

    labels.first(max_depth)
  end

  def folder_key_for(path)
    folder_key = File.dirname(path.to_s)
    return if folder_key.blank? || folder_key == "."

    folder_key
  end

  def folder_options_at(folder_keys, prefix)
    folder_keys.each_with_object([]) do |folder_key, options|
      parts = folder_key.split("/")
      next unless parts.first(prefix.size) == prefix
      next if parts[prefix.size].blank?

      options << parts[prefix.size]
    end.uniq.sort
  end

  def folder_selection_for(folder_keys, max_depth)
    selected_parts = Array.new(max_depth)
    level_options = []
    prefix = []

    max_depth.times do |index|
      options = folder_options_at(folder_keys, prefix)
      selected = params[:"folder_level_#{index}"].to_s.presence
      selected = nil unless options.include?(selected)

      level_options << options
      selected_parts[index] = selected
      break if selected.blank?

      prefix << selected
    end

    [level_options, selected_parts]
  end

  def folder_selection_params(selected_parts)
    selected_parts.each_with_index.each_with_object({}) do |(part, index), selection_params|
      selection_params[:"folder_level_#{index}"] = part if part.present?
    end
  end

  def selected_folder_key(selected_parts, max_depth)
    return if max_depth.zero?
    return if selected_parts.compact.size < max_depth

    selected_parts.join("/")
  end

  def selected_folder_prefix(selected_parts)
    selected_parts.compact_blank.join("/").presence
  end

  def filter_params(selection_params, search_query)
    selection_params.merge(search_query.present? ? { q: search_query } : {})
  end

  def current_folder_for_selection(selected_folder_key, selected_folder_prefix, documents)
    return File.dirname(selected_folder_key) if selected_folder_key.present?
    return selected_folder_prefix if selected_folder_prefix.present?
    return search_result_folder_for(documents) if @search_query.present?

    params[:folder].to_s.presence
  end

  def search_result_folder_for(documents)
    folder_keys = documents.filter_map { |document| folder_key_for(document.folder_path) }.uniq
    return if folder_keys.blank?
    return File.dirname(folder_keys.first) if folder_keys.one?

    common_folder_prefix(folder_keys)
  end

  def common_folder_prefix(folder_keys)
    split_keys = folder_keys.map { |folder_key| folder_key.split("/") }
    prefix = split_keys.first.take_while.with_index do |part, index|
      split_keys.all? { |parts| parts[index] == part }
    end

    prefix.join("/").presence
  end

  def filtered_documents(scope, folder_prefix, search_query)
    documents = folder_prefix.present? ? documents_for_selected_folder(scope, folder_prefix) : scope.to_a
    return documents if search_query.blank?

    matching_documents(documents, search_query)
  end

  def documents_for_selected_folder(scope, folder_key)
    scope.select do |document|
      document.folder_path.to_s.start_with?("#{folder_key}/")
    end
  end

  def matching_documents(documents, query)
    terms = query.downcase.split(/\s+/)

    documents.select do |document|
      searchable_text = [
        document.title,
        document.description,
        document.folder_name,
        document.folder_path,
        document.file_name
      ].compact.join(" ").downcase

      terms.all? { |term| searchable_text.include?(term) }
    end
  end

  def folder_items_for(folder_key)
    current_parts = folder_key.to_s.split("/").reject(&:blank?)

    @documents.each_with_object({}) do |document, folders|
      parts = document.folder_path.to_s.split("/")
      next unless parts.first(current_parts.size) == current_parts
      next unless parts.size > current_parts.size + 1

      child_key = parts.first(current_parts.size + 1).join("/")
      folders[child_key] ||= []
      folders[child_key] << document
    end.sort.to_h.map do |child_key, documents|
      {
        key: child_key,
        name: File.basename(child_key),
        documents: documents,
        leaf: folder_items_for_leaf?(child_key),
        size: documents.sum { |document| document.file.attached? ? document.file.byte_size : 0 }
      }
    end
  end

  def folder_items_for_leaf?(folder_key)
    current_parts = folder_key.to_s.split("/").reject(&:blank?)

    @documents.none? do |document|
      parts = document.folder_path.to_s.split("/")
      parts.first(current_parts.size) == current_parts && parts.size > current_parts.size + 1
    end
  end

  def breadcrumbs_for(folder_key)
    parts = folder_key.to_s.split("/").reject(&:blank?)
    [{ name: "Home", key: nil }] + parts.each_index.map do |index|
      { name: parts[index], key: parts.first(index + 1).join("/") }
    end
  end

  def documents_for_folder(folder_key)
    safe_key = ActiveRecord::Base.sanitize_sql_like(folder_key.to_s)
    visible_documents_scope(Document.includes(file_attachment: :blob)).where("folder_path LIKE ?", "#{safe_key}/%").order(:folder_path)
  end

  def build_folder_zip(folder_key, documents, request_id)
    zip_dir = Rails.root.join("tmp", "folder_downloads")
    FileUtils.mkdir_p(zip_dir)
    zip_path = zip_dir.join("#{request_id}-#{File.basename(folder_key).parameterize}.zip")

    FileUtils.rm_f(zip_path)
    Zip::File.open(zip_path, create: true) do |zip|
      documents.each do |document|
        entry_name = document.folder_path.delete_prefix("#{folder_key}/")
        zip.get_output_stream(entry_name) do |output|
          document.file.blob.open do |file|
            IO.copy_stream(file, output)
          end
        end
      end
    end

    zip_path
  end

  def folder_zip_filename(folder_key)
    parts = folder_key.to_s.split("/").reject(&:blank?)
    data_type = parts.last.presence || "Folder"
    village = parts[-2].presence
    filename = [data_type, formatted_village_name(village)].compact.join(" ")

    "#{sanitize_filename(filename)}.zip"
  end

  def formatted_village_name(village)
    village.to_s.strip.gsub(/\s+-\s+/, "_").presence
  end

  def sanitize_filename(filename)
    filename.gsub(/[^\w.\- ]+/, "_").squish
  end

  def deliver_admin_otp(request)
    AdminOtpDelivery.deliver!(download_request: request, otp: request.plain_otp)
  end

  def otp_delivery_notice(delivery_channel, folder: false)
    target = folder ? "Folder OTP" : "OTP"
    destination = delivery_channel == :sms ? "the admin mobile number" : "the admin email address"

    "#{target} has been sent to #{destination}."
  end
end
