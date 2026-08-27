require "test_helper"
require "zip"

class DocumentsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @tmp_dirs = []
  end

  teardown do
    @tmp_dirs.each { |dir| FileUtils.rm_rf(dir) }
  end

  test "admin can upload GIS zip archive from dashboard" do
    admin = create_user(
      email: "zip-upload-admin@example.com",
      employee_code: User::ADMIN_EMPLOYEE_CODE
    )
    archive = build_gis_archive

    login_as(admin)

    assert_difference -> { Document.count }, 1 do
      post documents_path, params: {
        gis_archive: Rack::Test::UploadedFile.new(archive.to_s, "application/zip")
      }
    end

    assert_redirected_to root_path
    assert_match "GIS upload complete", flash[:notice]
    assert_equal "CG/Raigarh/Tamnar/470604 - Sample Village/Khasra/470604_map.shp", Document.order(:created_at).last.folder_path
  end

  test "admin dashboard shows zip only upload control" do
    admin = create_user(
      email: "folder-input-admin@example.com",
      employee_code: User::ADMIN_EMPLOYEE_CODE
    )

    login_as(admin)
    get root_path

    assert_response :success
    assert_select "input#gis-folder-input", false
    assert_select "input#gis-archive-input[name='gis_archive'][accept*='.zip'][required]"
    assert_includes response.body, "GIS ZIP archive"
    assert_includes response.body, "Upload the complete GIS folder as one ZIP file"
  end

  test "admin sees zip guidance after multipart limit redirect" do
    admin = create_user(
      email: "multipart-limit-admin@example.com",
      employee_code: User::ADMIN_EMPLOYEE_CODE
    )

    login_as(admin)
    get documents_path(upload_error: "too_many_upload_parts")

    assert_response :success
    assert_includes response.body, "one ZIP archive"
    assert_includes response.body, "GIS ZIP archive"
  end

  test "admin cannot upload GIS folder params" do
    admin = create_user(
      email: "folder-param-admin@example.com",
      employee_code: User::ADMIN_EMPLOYEE_CODE
    )
    upload = build_gis_folder_upload

    login_as(admin)

    assert_no_difference -> { Document.count } do
      post documents_path, params: {
        gis_files: upload[:files],
        gis_file_paths_payload: JSON.generate(upload[:paths])
      }
    end

    assert_redirected_to root_path
    assert_match "Please select a GIS ZIP archive", flash[:alert]
  end

  test "non admin cannot upload GIS zip archive" do
    user = create_user(employee_code: "1349")
    archive = build_gis_archive

    login_as(user)

    assert_no_difference -> { Document.count } do
      post documents_path, params: {
        gis_archive: Rack::Test::UploadedFile.new(archive.to_s, "application/zip")
      }
    end

    assert_redirected_to root_path
    assert_equal "Only admin can access this page.", flash[:alert]
  end

  test "admin upload requires folder selection" do
    admin = create_user(
      email: "zip-required-admin@example.com",
      employee_code: User::ADMIN_EMPLOYEE_CODE
    )

    login_as(admin)

    assert_no_difference -> { Document.count } do
      post documents_path
    end

    assert_redirected_to root_path
    assert_match "Please select a GIS ZIP archive", flash[:alert]
  end

  private

  def create_user(attributes = {})
    employee_code = attributes.fetch(:employee_code, SecureRandom.random_number(10_000).to_s)

    User.create!({
      name: "ESS User",
      email: "employee-#{employee_code}@example.com",
      role: "user",
      password: "password123",
      employee_code: employee_code
    }.merge(attributes))
  end

  def login_as(user)
    get signed_ess_login_path(user.employee_code)
    assert_redirected_to root_path
  end

  def build_gis_folder_upload
    tmp_dir = Dir.mktmpdir("gis-controller-test-", Rails.root.join("tmp").to_s)
    @tmp_dirs << tmp_dir
    tmp_path = Pathname.new(tmp_dir)
    workbook_path = tmp_path.join("villages.xlsx")
    shape_path = tmp_path.join("CG", "Khasra", "470604_map.shp")

    build_village_workbook(workbook_path)
    FileUtils.mkdir_p(shape_path.dirname)
    File.write(shape_path, "sample shape data")

    {
      files: [
        Rack::Test::UploadedFile.new(workbook_path.to_s, "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"),
        Rack::Test::UploadedFile.new(shape_path.to_s, "application/octet-stream")
      ],
      paths: [
        "GIS/villages.xlsx",
        "GIS/CG/Khasra/470604_map.shp"
      ]
    }
  end

  def build_gis_archive
    tmp_dir = Dir.mktmpdir("gis-controller-test-", Rails.root.join("tmp").to_s)
    @tmp_dirs << tmp_dir
    tmp_path = Pathname.new(tmp_dir)
    workbook_path = tmp_path.join("villages.xlsx")
    archive_path = tmp_path.join("gis.zip")

    build_village_workbook(workbook_path)

    Zip::File.open(archive_path, create: true) do |zip|
      zip.add("GIS/villages.xlsx", workbook_path.to_s)
      zip.get_output_stream("GIS/CG/Khasra/470604_map.shp") { |file| file.write("sample shape data") }
    end

    archive_path
  end

  def build_village_workbook(path)
    strings = [
      "State Name", "District Name", "CD Block Name", "Village Code", "Village Name",
      "CG", "Raigarh", "Tamnar", "470604", "Sample Village"
    ]

    Zip::File.open(path, create: true) do |zip|
      zip.get_output_stream("xl/sharedStrings.xml") do |file|
        file.write(shared_strings_xml(strings))
      end

      zip.get_output_stream("xl/worksheets/sheet1.xml") do |file|
        file.write(village_sheet_xml)
      end
    end
  end

  def shared_strings_xml(strings)
    items = strings.map { |value| "<si><t>#{ERB::Util.html_escape(value)}</t></si>" }.join
    %(<?xml version="1.0" encoding="UTF-8"?><sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">#{items}</sst>)
  end

  def village_sheet_xml
    <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
        <sheetData>
          <row r="1">
            <c r="A1" t="s"><v>0</v></c>
            <c r="B1" t="s"><v>1</v></c>
            <c r="C1" t="s"><v>2</v></c>
            <c r="D1" t="s"><v>3</v></c>
            <c r="E1" t="s"><v>4</v></c>
          </row>
          <row r="2">
            <c r="A2" t="s"><v>5</v></c>
            <c r="B2" t="s"><v>6</v></c>
            <c r="C2" t="s"><v>7</v></c>
            <c r="D2" t="s"><v>8</v></c>
            <c r="E2" t="s"><v>9</v></c>
          </row>
        </sheetData>
      </worksheet>
    XML
  end
end
