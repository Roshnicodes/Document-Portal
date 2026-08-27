require "nokogiri"
require "zip"

class GisImporter
  STATE_FOLDERS = %w[CG JH MP].freeze
  TEMP_FILE_PREFIXES = [ ".", "~$", ".~lock" ].freeze

  Result = Struct.new(:imported, :skipped, :stale_removed, :batch_id, keyword_init: true)

  Village = Struct.new(:state, :district, :block, :code, :name, keyword_init: true) do
    def complete?
      [ state, district, block, code, name ].all?(&:present?)
    end

    def folder_name
      "#{code} - #{name}"
    end
  end

  class SharedStringsParser < Nokogiri::XML::SAX::Document
    attr_reader :strings

    def initialize
      @strings = []
      @current = nil
      @inside_text = false
    end

    def start_element(name, _attrs = [])
      @current = "" if name == "si"
      @inside_text = true if name == "t"
    end

    def characters(string)
      @current << string if @inside_text && @current
    end

    def end_element(name)
      @inside_text = false if name == "t"
      return unless name == "si"

      @strings << @current.to_s
      @current = nil
    end
  end

  class VillageSheetParser < Nokogiri::XML::SAX::Document
    attr_reader :villages

    def initialize(shared_strings)
      @shared_strings = shared_strings
      @villages = {}
      @headers = []
      @row = []
      @cell_ref = nil
      @cell_type = nil
      @cell_value = +""
      @inside_value = false
    end

    def start_element(name, attrs = [])
      attributes = attrs.to_h
      @row = [] if name == "row"

      if name == "c"
        @cell_ref = attributes["r"]
        @cell_type = attributes["t"]
        @cell_value = +""
      end

      @inside_value = true if name == "v"
    end

    def characters(string)
      @cell_value << string if @inside_value
    end

    def end_element(name)
      @inside_value = false if name == "v"
      finish_cell if name == "c"
      finish_row if name == "row"
    end

    private

    def finish_cell
      column = @cell_ref[/[A-Z]+/]
      index = column.chars.reduce(0) { |sum, char| (sum * 26) + char.ord - 64 } - 1
      value = @cell_type == "s" ? @shared_strings[@cell_value.to_i] : @cell_value
      @row[index] = clean(value)
    end

    def finish_row
      if @headers.blank?
        @headers = @row
        return
      end

      row = @headers.zip(@row).to_h
      village = Village.new(
        state: clean(row["State Name"]),
        district: clean(row["District Name"]),
        block: clean(row["CD Block Name"]),
        code: clean(row["Village Code"]),
        name: clean(row["Village Name"])
      )
      @villages[village.code] = village if village.complete?
    end

    def clean(value)
      GisImporter.clean(value)
    end
  end

  def self.import_folder!(folder, uploaded_by:, remove_stale: false)
    new(folder, uploaded_by: uploaded_by, remove_stale: remove_stale).import!
  end

  def self.import_archive!(archive, uploaded_by:, remove_stale: false)
    validate_archive!(archive)

    Dir.mktmpdir("gis-upload-", Rails.root.join("tmp").to_s) do |dir|
      temp_dir = Pathname.new(dir)
      archive_path = temp_dir.join("upload.zip")
      extracted_path = temp_dir.join("extracted")

      copy_upload(archive, archive_path)
      FileUtils.mkdir_p(extracted_path)
      extract_archive(archive_path, extracted_path)

      import_folder!(import_root_for(extracted_path), uploaded_by: uploaded_by, remove_stale: remove_stale)
    end
  end

  def self.import_uploads!(uploads, relative_paths:, uploaded_by:, remove_stale: false)
    uploads = Array(uploads).compact
    relative_paths = Array(relative_paths)
    raise ArgumentError, "Please select the complete GIS folder to upload." if uploads.empty?

    Dir.mktmpdir("gis-folder-upload-", Rails.root.join("tmp").to_s) do |dir|
      upload_root = Pathname.new(dir).join("selected")
      FileUtils.mkdir_p(upload_root)

      uploads.each_with_index do |upload, index|
        relative_path = upload_relative_path(upload, relative_paths[index])
        target = safe_import_target(relative_path, upload_root)
        FileUtils.mkdir_p(target.dirname)
        copy_upload(upload, target)
      end

      import_folder!(import_root_for(upload_root), uploaded_by: uploaded_by, remove_stale: remove_stale)
    end
  end

  def self.validate_archive!(archive)
    filename = if archive.respond_to?(:original_filename)
      archive.original_filename
    else
      File.basename(archive.to_s)
    end

    raise ArgumentError, "Please select a GIS .zip archive to upload." if filename.blank?
    raise ArgumentError, "Please upload a .zip archive containing the GIS folder." unless File.extname(filename).downcase == ".zip"
  end

  def self.copy_upload(upload, destination)
    File.open(destination, "wb") do |file|
      if upload.respond_to?(:tempfile) && upload.tempfile
        upload.tempfile.rewind
        IO.copy_stream(upload.tempfile, file)
      elsif upload.respond_to?(:read)
        upload.rewind if upload.respond_to?(:rewind)
        file.write(upload.read)
      else
        File.open(upload.to_s, "rb") { |source| IO.copy_stream(source, file) }
      end
    end
  end

  def self.extract_archive(archive_path, destination)
    Zip::File.open(archive_path) do |zip|
      zip.each do |entry|
        next if entry.directory?

        target = safe_import_target(entry.name, destination)
        FileUtils.mkdir_p(target.dirname)
        entry.get_input_stream do |input|
          File.open(target, "wb") { |output| IO.copy_stream(input, output) }
        end
      end
    end
  end

  def self.upload_relative_path(upload, provided_path)
    relative_path = provided_path.presence
    relative_path ||= upload.original_filename if upload.respond_to?(:original_filename)
    relative_path ||= File.basename(upload.to_s)
    relative_path.to_s.tr("\\", "/")
  end

  def self.safe_import_target(entry_name, destination)
    entry_path = Pathname.new(entry_name.to_s)

    if entry_path.absolute? || entry_path.each_filename.any? { |part| part == ".." }
      raise ArgumentError, "Upload contains an unsafe file path: #{entry_name}"
    end

    target = destination.join(entry_path).cleanpath
    destination_prefix = "#{destination.cleanpath}#{File::SEPARATOR}"

    unless target.to_s.start_with?(destination_prefix)
      raise ArgumentError, "Upload contains an unsafe file path: #{entry_name}"
    end

    target
  end

  def self.import_root_for(destination)
    children = destination.children.reject { |path| ignored_archive_root?(path) }
    return children.first if children.one? && children.first.directory? && spreadsheet_workbook?(children.first)

    destination
  end

  def self.spreadsheet_workbook?(folder)
    spreadsheet_workbook(folder).present?
  end

  def self.spreadsheet_workbook(folder)
    folder.children.find do |path|
      path.file? && path.basename.to_s.end_with?(".xlsx") && !temporary_file?(path)
    end
  end

  def self.ignored_archive_root?(path)
    path.basename.to_s == "__MACOSX" || temporary_file?(path)
  end

  def self.spreadsheet_villages(folder)
    workbook = spreadsheet_workbook(folder)
    return {} unless workbook

    Zip::File.open(workbook) do |zip|
      shared_strings = SharedStringsParser.new
      Nokogiri::XML::SAX::Parser.new(shared_strings).parse(zip.get_input_stream("xl/sharedStrings.xml"))

      villages = VillageSheetParser.new(shared_strings.strings)
      Nokogiri::XML::SAX::Parser.new(villages).parse(zip.get_input_stream("xl/worksheets/sheet1.xml"))
      villages.villages
    end
  end

  def self.first_dbf_record(path)
    File.open(path, "rb") do |file|
      header = file.read(32)
      header_length = header.byteslice(8, 2).unpack1("v")
      record_length = header.byteslice(10, 2).unpack1("v")
      fields = []

      while (descriptor = file.read(32))
        break if descriptor.bytes.first == 13

        fields << [
          descriptor.byteslice(0, 11).delete("\x00"),
          descriptor.byteslice(16).ord
        ]
      end

      file.seek(header_length)
      record = file.read(record_length)
      return {} if record.blank? || record.bytes.first == 42

      position = 1
      fields.each_with_object({}) do |(name, length), values|
        values[name] = clean(record.byteslice(position, length))
        position += length
      end
    end
  end

  def self.dbf_village(path, state)
    values = first_dbf_record(path)
    return unless values.present?

    case state
    when "CG", "JH"
      Village.new(
        state: state,
        district: clean(values["State_LGD"]),
        block: clean(values["Dist_LGD"]),
        code: clean(values["Vill_Cat"]),
        name: clean(values["Subdis_Typ"])
      )
    when "MP"
      Village.new(
        state: state,
        district: clean(values["teh_cd"]),
        block: clean(values["dist_cd"]),
        code: clean(values["vil_nm_e"]),
        name: village_name_from(path)
      )
    end
  end

  def self.metadata_for(path, folder, spreadsheet_index)
    relative_path = path.relative_path_from(folder)
    state = state_for(relative_path)
    code = village_code_from(path)
    return spreadsheet_index[code] if valid_village?(spreadsheet_index[code])

    dbf_path = path.sub_ext(".dbf")
    village = dbf_village(dbf_path, state) if state.present? && dbf_path.file?
    village if valid_village?(village)
  end

  def self.document_path_for(village, data_type, filename)
    [ village.state, village.district, village.block, village.folder_name, data_type, filename ].join("/")
  end

  def self.data_type_for(relative_path)
    parts = relative_path.each_filename.to_a
    return "Khasra" if parts.include?("Khasra")
    return "Village Boundary" if parts.include?("Village Boundary")

    "Other"
  end

  def self.importable_file?(path)
    path.file? && !temporary_file?(path) && path.extname.downcase != ".xlsx"
  end

  def self.temporary_file?(path)
    TEMP_FILE_PREFIXES.any? { |prefix| path.basename.to_s.start_with?(prefix) }
  end

  def self.state_for(path)
    parts = path.each_filename.to_a
    STATE_FOLDERS.find { |state| parts.include?(state) }
  end

  def self.village_code_from(path)
    path.basename(path.extname).to_s[/\d{5,7}/]
  end

  def self.village_name_from(path)
    path.basename(path.extname).to_s.sub(/_\d+\z/, "").tr("_", " ").squish
  end

  def self.valid_village?(village)
    return false unless village&.complete?
    return false unless STATE_FOLDERS.include?(village.state)
    return false if village.district.match?(/\A\d+\z/)
    return false if village.block.match?(/\A\d+\z/)
    return false if village.name.match?(/\A_+\z|fully_urban|other/i)

    village.code.match?(/\A\d{6}\z/)
  end

  def self.clean(value)
    value.to_s.delete("\u001A").squish.presence
  end

  def initialize(folder, uploaded_by:, remove_stale: false)
    @folder = Pathname.new(folder.to_s).expand_path
    @uploaded_by = uploaded_by
    @remove_stale = remove_stale
  end

  def import!
    raise ArgumentError, "Only admin users can import GIS data." unless @uploaded_by&.admin?
    raise ArgumentError, "Folder not found: #{@folder}" unless @folder.directory?

    spreadsheet_index = self.class.spreadsheet_villages(@folder)
    files = @folder.find.select { |path| self.class.importable_file?(path) }
    raise ArgumentError, "No GIS files found in the uploaded folder." if files.empty?

    batch_id = SecureRandom.uuid
    import_rows = import_rows_for(files, spreadsheet_index)
    raise ArgumentError, "No GIS files matched state/district/block/village metadata." if import_rows.empty?

    stale_removed = remove_stale_documents(import_rows.map(&:folder_path))
    imported = import_rows.sum { |row| import_document(row, batch_id) }

    Result.new(
      imported: imported,
      skipped: files.size - import_rows.size,
      stale_removed: stale_removed,
      batch_id: batch_id
    )
  end

  private

  ImportRow = Struct.new(:path, :village, :data_type, :folder_path, keyword_init: true)

  def import_rows_for(files, spreadsheet_index)
    files.filter_map do |path|
      village = self.class.metadata_for(path, @folder, spreadsheet_index)
      next unless village&.complete?

      data_type = self.class.data_type_for(path.relative_path_from(@folder))
      folder_path = self.class.document_path_for(village, data_type, path.basename.to_s)
      ImportRow.new(path: path, village: village, data_type: data_type, folder_path: folder_path)
    end
  end

  def remove_stale_documents(current_folder_paths)
    return 0 unless @remove_stale

    stale_documents = Document.where("description LIKE ?", "Preloaded GIS data%")
      .or(Document.where("folder_path LIKE ?", "GIS/%"))
      .or(Document.where("folder_path LIKE ?", "CG/%"))
      .or(Document.where("folder_path LIKE ?", "JH/%"))
      .or(Document.where("folder_path LIKE ?", "MP/%"))
      .where.not(folder_path: current_folder_paths)

    stale_count = stale_documents.count
    stale_documents.find_each(&:destroy!)
    stale_count
  end

  def import_document(row, batch_id)
    title = row.path.basename.to_s
    group_name = File.dirname(row.folder_path).split("/").join(" / ")

    document = Document.find_or_initialize_by(folder_name: group_name, folder_path: row.folder_path)
    document.assign_attributes(
      uploaded_by: @uploaded_by,
      title: title,
      description: "Preloaded GIS data for #{row.village.state} / #{row.village.district} / #{row.village.block} / #{row.village.folder_name} / #{row.data_type}",
      upload_batch_id: batch_id
    )

    document.file.purge if document.file.attached?
    File.open(row.path, "rb") do |file|
      document.file.attach(io: file, filename: title, content_type: Marcel::MimeType.for(row.path))
      document.save!
    end

    1
  end
end
