require "test_helper"

class SessionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @secret = "test-shared-secret"
    @user = User.create!(
      name: "ESS User",
      email: "ess.user@example.com",
      role: "user",
      password: "password123",
      employee_code: "1349",
      office_name: "TO-Pati"
    )
  end

  test "signed ESS login works when employee code exists" do
    with_ess_secret do
      get signed_ess_login_path(@user.employee_code, signed_params(@user.employee_code))
    end

    assert_redirected_to root_path
    assert_equal @user.id, session[:user_id]
  end

  test "signed ESS login rejects unknown employee code" do
    with_ess_secret do
      get signed_ess_login_path("999999", signed_params("999999"))
    end

    assert_redirected_to ess_login_path
    assert_nil session[:user_id]
  end

  test "signed ESS login rejects invalid signature" do
    with_ess_secret do
      get signed_ess_login_path(@user.employee_code, expires_at: 5.minutes.from_now.to_i, signature: "bad")
    end

    assert_redirected_to ess_login_path
    assert_nil session[:user_id]
  end

  test "signed ESS login rejects expired link" do
    with_ess_secret do
      get signed_ess_login_path(@user.employee_code, signed_params(@user.employee_code, expires_at: 1.minute.ago.to_i))
    end

    assert_redirected_to ess_login_path
    assert_nil session[:user_id]
  end

  test "ESS login page is an access fallback without password form" do
    get ess_login_path

    assert_response :unauthorized
    assert_includes response.body, "Please open Document Portal from ESS."
  end

  private

  def signed_params(employee_code, expires_at: 5.minutes.from_now.to_i)
    {
      expires_at: expires_at,
      signature: OpenSSL::HMAC.hexdigest("sha256", @secret, "#{employee_code}:#{expires_at}")
    }
  end

  def with_ess_secret
    old_secret = ENV["ESS_LOGIN_SECRET"]
    ENV["ESS_LOGIN_SECRET"] = @secret
    yield
  ensure
    ENV["ESS_LOGIN_SECRET"] = old_secret
  end
end
