# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Example:
#
#   ["Action", "Comedy", "Drama", "Horror"].each do |genre_name|
#     MovieGenre.find_or_create_by!(name: genre_name)
#   end
admin = User.find_or_initialize_by(email: "admin@example.com")
admin.assign_attributes(name: "Admin Department", role: "admin")
admin.password = "password123" if admin.new_record?
admin.save!

user = User.find_or_initialize_by(email: "user@example.com")
user.assign_attributes(name: "User Department", role: "user")
user.password = "password123" if user.new_record?
user.save!

puts "Seeded demo accounts:"
puts "Admin: admin@example.com / password123"
puts "User: user@example.com / password123"
