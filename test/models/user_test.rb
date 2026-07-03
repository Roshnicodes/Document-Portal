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
end
