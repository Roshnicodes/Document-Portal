# frozen_string_literal: true

class MultipartLimitRescue
  REDIRECT_LOCATION = "/documents?upload_error=too_many_upload_parts".freeze

  def initialize(app)
    @app = app
  end

  def call(env)
    @app.call(env)
  rescue Rack::Multipart::MultipartPartLimitError, Rack::Multipart::MultipartTotalPartLimitError
    [
      303,
      {
        "Content-Type" => "text/html; charset=utf-8",
        "Content-Length" => "0",
        "Location" => REDIRECT_LOCATION
      },
      []
    ]
  end
end
