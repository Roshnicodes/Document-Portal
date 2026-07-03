require "zip"
require "nokogiri"

class EmployeeImporter
  HEADER_MAP = {
    "Name" => :name,
    "Email" => :email,
    "Employee Code" => :employee_code,
    "Mobile Number" => :mobile_number,
    "L1 Code" => :l1_code,
    "L1 Name" => :l1_name,
    "L2 Code" => :l2_code,
    "L2 Name" => :l2_name,
    "L3 Code" => :l3_code,
    "L3 Name" => :l3_name,
    "Designation" => :designation,
    "Position" => :position,
    "Office Type" => :office_type,
    "Office Name" => :office_name,
    "Department" => :department
  }.freeze

  Result = Struct.new(:created, :updated, :skipped, keyword_init: true)

  def self.import!(path)
    new(path).import!
  end

  def initialize(path)
    @path = Pathname.new(path.to_s).expand_path
  end

  def import!
    raise ArgumentError, "Employee file not found: #{@path}" unless @path.file?

    result = Result.new(created: 0, updated: 0, skipped: 0)

    rows.each do |attributes|
      if attributes[:employee_code].blank?
        result.skipped += 1
        next
      end

      user = User.find_or_initialize_by(employee_code: attributes[:employee_code])
      attributes[:name] = "Employee #{attributes[:employee_code]}" if attributes[:name].blank?
      user.email = generated_email(attributes[:employee_code]) if attributes[:email].blank?
      user.assign_attributes(attributes.compact)
      user.role = "user"
      user.password = SecureRandom.hex(24) if user.new_record?
      user.save!

      user.previously_new_record? ? result.created += 1 : result.updated += 1
    end

    result
  end

  private

  def rows
    @rows ||= begin
      header = nil

      read_sheet.filter_map do |values|
        if header.blank?
          header = values
          next
        end

        attributes = header.zip(values).each_with_object({}) do |(column, value), row|
          key = HEADER_MAP[column.to_s.squish]
          row[key] = value.to_s.squish.presence if key
        end
        attributes.presence
      end
    end
  end

  def read_sheet
    Zip::File.open(@path) do |zip|
      strings = shared_strings(zip)
      sheet = zip.find_entry("xl/worksheets/sheet1.xml")
      raise ArgumentError, "Sheet 1 not found in #{@path}" unless sheet

      document = Nokogiri::XML(sheet.get_input_stream.read)
      document.remove_namespaces!
      document.xpath("//row").map do |row|
        values_for(row, strings)
      end
    end
  end

  def shared_strings(zip)
    entry = zip.find_entry("xl/sharedStrings.xml")
    return [] unless entry

    document = Nokogiri::XML(entry.get_input_stream.read)
    document.remove_namespaces!
    document.xpath("//si").map { |node| node.xpath(".//t").map(&:text).join }
  end

  def values_for(row, strings)
    values = []
    row.xpath("./c").each do |cell|
      index = column_index(cell["r"].to_s[/[A-Z]+/])
      raw_value = cell.at_xpath("./v")&.text.to_s
      values[index] = cell["t"] == "s" ? strings[raw_value.to_i] : raw_value
    end
    values
  end

  def column_index(column)
    column.to_s.chars.reduce(0) { |sum, char| (sum * 26) + char.ord - 64 } - 1
  end

  def generated_email(employee_code)
    "employee-#{employee_code}@ess.local"
  end
end
