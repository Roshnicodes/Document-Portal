require "test_helper"

class MultipartLimitRescueTest < ActiveSupport::TestCase
  test "redirects multipart file limit errors back to documents" do
    app = MultipartLimitRescue.new(->(_env) { raise Rack::Multipart::MultipartPartLimitError })

    status, headers, body = app.call({})

    assert_equal 303, status
    assert_equal "/documents?upload_error=too_many_upload_parts", headers["Location"]
    assert_equal [], body
  end

  test "redirects multipart total part limit errors back to documents" do
    app = MultipartLimitRescue.new(->(_env) { raise Rack::Multipart::MultipartTotalPartLimitError })

    status, headers, body = app.call({})

    assert_equal 303, status
    assert_equal "/documents?upload_error=too_many_upload_parts", headers["Location"]
    assert_equal [], body
  end
end
