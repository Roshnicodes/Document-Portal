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

  test "configured senior employee codes have full data access" do
    assert User.new(employee_code: "002").full_data_access?
    assert User.new(employee_code: "2").full_data_access?
    assert User.new(employee_code: "397").full_data_access?
    assert User.new(employee_code: "840").full_data_access?
    assert User.new(employee_code: "1495").full_data_access?
  end

  test "only fco coordinator designation has full data access" do
    assert User.new(designation: "FCO Coordinator/PE").full_data_access?
    assert User.new(designation: "FCO- Coordinator").full_data_access?

    assert_not User.new(designation: "PMU Coordinator -Shahdol").full_data_access?
    assert_not User.new(department: "GIS").full_data_access?
    assert_not User.new(department: "Water Resource Development").full_data_access?
    assert_not User.new(office_type: "FCO-Rajpur").full_data_access?
    assert_not User.new(office_name: "FCO-Bhabra").full_data_access?
  end
end
