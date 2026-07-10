require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "location scope is derived from TO office name" do
    user = User.new(office_name: "To-Sendhwa (Niwali HQ)")

    assert_equal "Sendhwa", user.location_scope_name
  end

  test "location scope is derived from FCO office name" do
    user = User.new(office_name: "FCO-Rajpur")

    assert_equal "Rajpur", user.location_scope_name
  end

  test "employee code 397 is the only admin code" do
    admin = User.new(name: "Admin", email: "admin@example.com", role: "user", password: "password123", employee_code: "397")
    other = User.new(name: "Other", email: "other@example.com", role: "admin", password: "password123", employee_code: "398")

    admin.valid?
    other.valid?

    assert admin.admin?
    assert other.user?
  end

  test "employee code 397 is admin even when saved role is stale" do
    admin = User.create!(name: "Admin", email: "admin-stale@example.com", password: "password123", employee_code: "397")
    admin.update_column(:role, "user")
    admin.reload

    assert admin.admin?
    admin.ensure_canonical_role!

    assert_equal "admin", admin.reload.role
  end
end
