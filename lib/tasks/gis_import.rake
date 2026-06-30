require "nokogiri"
require "zip"

module GisImport
  module_function

  STATE_FOLDERS = %w[CG JH MP].freeze
  TEMP_FILE_PREFIXES = [".", "~$", ".~lock"].freeze

  Village = Struct.new(:state, :district, :block, :code, :name, keyword_init: true) do
    def complete?
      [state, district, block, code, name].all?(&:present?)
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
      GisImport.clean(value)
    end
  end

  def spreadsheet_villages(folder)
    workbook = folder.children.find do |path|
      path.file? && path.basename.to_s.end_with?(".xlsx") && !temporary_file?(path)
    end
    return {} unless workbook

    Zip::File.open(workbook) do |zip|
      shared_strings = SharedStringsParser.new
      Nokogiri::XML::SAX::Parser.new(shared_strings).parse(zip.get_input_stream("xl/sharedStrings.xml"))

      villages = VillageSheetParser.new(shared_strings.strings)
      Nokogiri::XML::SAX::Parser.new(villages).parse(zip.get_input_stream("xl/worksheets/sheet1.xml"))
      villages.villages
    end
  end

  def first_dbf_record(path)
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

  def dbf_village(path, state)
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

  def metadata_for(path, folder, spreadsheet_index)
    relative_path = path.relative_path_from(folder)
    state = state_for(relative_path)
    code = village_code_from(path)
    return spreadsheet_index[code] if valid_village?(spreadsheet_index[code])

    dbf_path = path.sub_ext(".dbf")
    village = dbf_village(dbf_path, state) if state.present? && dbf_path.file?
    village if valid_village?(village)
  end

  def document_path_for(village, data_type, filename)
    [village.state, village.district, village.block, village.folder_name, data_type, filename].join("/")
  end

  def data_type_for(relative_path)
    parts = relative_path.each_filename.to_a
    return "Khasra" if parts.include?("Khasra")
    return "Village Boundary" if parts.include?("Village Boundary")

    "Other"
  end

  def importable_file?(path)
    path.file? && !temporary_file?(path) && path.extname.downcase != ".xlsx"
  end

  def temporary_file?(path)
    TEMP_FILE_PREFIXES.any? { |prefix| path.basename.to_s.start_with?(prefix) }
  end

  def state_for(path)
    parts = path.each_filename.to_a
    STATE_FOLDERS.find { |state| parts.include?(state) }
  end

  def village_code_from(path)
    path.basename(path.extname).to_s[/\d{5,7}/]
  end

  def village_name_from(path)
    path.basename(path.extname).to_s.sub(/_\d+\z/, "").tr("_", " ").squish
  end

  def valid_village?(village)
    return false unless village&.complete?
    return false unless STATE_FOLDERS.include?(village.state)
    return false if village.district.match?(/\A\d+\z/)
    return false if village.block.match?(/\A\d+\z/)
    return false if village.name.match?(/\A_+\z|fully_urban|other/i)

    village.code.match?(/\A\d{6}\z/)
  end

  def clean(value)
    value.to_s.delete("\u001A").squish.presence
  end
end

namespace :gis do
  desc "Import the GIS folder into document records and Active Storage"
  task import: :environment do
    folder = Pathname.new(ENV.fetch("FOLDER", Rails.root.join("..", "GIS").to_s)).expand_path
    admin_email = ENV.fetch("ADMIN_EMAIL", "admin@example.com")
    admin = User.find_by!(email: admin_email.downcase)

    abort "Folder not found: #{folder}" unless folder.directory?

    spreadsheet_index = GisImport.spreadsheet_villages(folder)
    files = folder.find.select { |path| GisImport.importable_file?(path) }
    abort "No files found in: #{folder}" if files.empty?

    batch_id = SecureRandom.uuid
    import_rows = files.filter_map do |path|
      village = GisImport.metadata_for(path, folder, spreadsheet_index)
      next unless village&.complete?

      data_type = GisImport.data_type_for(path.relative_path_from(folder))
      folder_path = GisImport.document_path_for(village, data_type, path.basename.to_s)
      [path, village, data_type, folder_path]
    end
    abort "No GIS files matched state/district/block/village metadata." if import_rows.empty?

    current_folder_paths = import_rows.map(&:last)
    stale_documents = Document.where("description LIKE ?", "Preloaded GIS data%")
      .or(Document.where("folder_path LIKE ?", "GIS/%"))
      .or(Document.where("folder_path LIKE ?", "CG/%"))
      .or(Document.where("folder_path LIKE ?", "JH/%"))
      .or(Document.where("folder_path LIKE ?", "MP/%"))
      .where.not(folder_path: current_folder_paths)
    stale_count = stale_documents.count
    stale_documents.find_each(&:destroy!)
    puts "Removed #{stale_count} stale GIS records." if stale_count.positive?

    imported = 0
    skipped = files.size - import_rows.size
    import_rows.each do |path, village, data_type, folder_path|
      title = path.basename.to_s
      group_name = File.dirname(folder_path).split("/").join(" / ")

      document = Document.find_or_initialize_by(folder_name: group_name, folder_path: folder_path)
      document.assign_attributes(
        uploaded_by: admin,
        title: title,
        description: "Preloaded GIS data for #{village.state} / #{village.district} / #{village.block} / #{village.folder_name} / #{data_type}",
        upload_batch_id: batch_id
      )

      document.file.purge if document.file.attached?
      file = File.open(path, "rb")
      begin
        document.file.attach(io: file, filename: title, content_type: Marcel::MimeType.for(path))
        document.save!
      ensure
        file.close
      end
      imported += 1
      puts "Imported #{folder_path}"
    end

    puts "Skipped #{skipped} files without complete location metadata." if skipped.positive?
    puts "Done. Imported #{imported} GIS files."
  end
end
