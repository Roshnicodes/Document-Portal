require Rails.root.join("app/services/employee_importer").to_s

namespace :employees do
  desc "Import ESS employee users from an XLSX file"
  task import: :environment do
    file = ENV.fetch("FILE", nil)
    abort "Usage: FILE=/path/to/employee_template.xlsx bin/rails employees:import" if file.blank?

    result = EmployeeImporter.import!(file)
    puts "Employee import complete. Created: #{result.created}, Updated: #{result.updated}, Skipped: #{result.skipped}."
  end
end
