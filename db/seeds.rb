# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Example:
#
#   ["Action", "Comedy", "Drama", "Horror"].each do |genre_name|
#     MovieGenre.find_or_create_by!(name: genre_name)
#   end
admin = User.find_or_initialize_by(employee_code: User::ADMIN_EMPLOYEE_CODE)
admin.email = "employee-#{User::ADMIN_EMPLOYEE_CODE}@ess.local" if admin.email.blank?
admin.assign_attributes(name: "Admin Department", role: "admin")
admin.password = "password123" if admin.new_record?
admin.save!

user = User.find_or_initialize_by(email: "user@example.com")
user.assign_attributes(
  name: "User Department",
  role: "user",
  employee_code: "DEMO-USER",
  office_type: "FCO-Rajpur",
  office_name: "TO-Pati",
  department: "Demo Access"
)
user.password = "password123" if user.new_record?
user.save!

puts "Seeded demo accounts:"
puts "Admin employee code: #{User::ADMIN_EMPLOYEE_CODE}"
puts "User: user@example.com / password123"
