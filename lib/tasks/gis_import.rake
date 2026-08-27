require Rails.root.join("app/services/gis_importer").to_s

namespace :gis do
  desc "Import the GIS folder into document records and Active Storage"
  task import: :environment do
    folder = Pathname.new(ENV.fetch("FOLDER", Rails.root.join("..", "GIS").to_s)).expand_path
    admin_email = ENV.fetch("ADMIN_EMAIL", "admin@example.com")
    admin = User.find_by!(email: admin_email.downcase)

    result = GisImporter.import_folder!(folder, uploaded_by: admin, remove_stale: true)

    puts "Removed #{result.stale_removed} stale GIS records." if result.stale_removed.positive?
    puts "Skipped #{result.skipped} files without complete location metadata." if result.skipped.positive?
    puts "Done. Imported #{result.imported} GIS files."
  end
end
