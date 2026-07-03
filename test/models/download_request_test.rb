require "test_helper"

class DownloadRequestTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(
      name: "Portal User",
      email: "portal.user@example.com",
      role: "user",
      password: "password123"
    )
  end

  test "folder OTP request requires download purpose" do
    assert_raises(ActiveRecord::RecordInvalid) do
      DownloadRequest.create_folder_with_otp!(
        folder_key: "MP/Barwani/Pati/478101 - Awali/Village Boundary",
        folder_name: "Village Boundary",
        user: @user,
        download_purpose: ""
      )
    end
  end

  test "folder OTP request requires at least 50 purpose words" do
    assert_raises(ActiveRecord::RecordInvalid) do
      DownloadRequest.create_folder_with_otp!(
        folder_key: "MP/Barwani/Pati/478101 - Awali/Village Boundary",
        folder_name: "Village Boundary",
        user: @user,
        download_purpose: "field verification work"
      )
    end
  end

  test "folder OTP request stores normalized download purpose" do
    purpose = Array.new(50) { |index| "word#{index}" }.join(" ")

    request = DownloadRequest.create_folder_with_otp!(
      folder_key: "MP/Barwani/Pati/478101 - Awali/Village Boundary",
      folder_name: "Village Boundary",
      user: @user,
      download_purpose: "  #{purpose}  "
    )

    assert_equal purpose, request.download_purpose
    assert_match(/\A\d{6}\z/, request.plain_otp)
  end
end
