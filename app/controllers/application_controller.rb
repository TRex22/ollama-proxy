class ApplicationController < ActionController::API
  include ActionController::HttpAuthentication::Token::ControllerMethods

  before_action :authenticate_user!

  private

  def authenticate_user!
    authenticate_or_request_with_http_token do |token, options|
      @current_user = User.find_by_token(token)
      @current_user.present?
    end
  end

  def current_user
    @current_user
  end

  def log_request(ollama_model: nil, server_used: nil, response_status: nil, response_time_ms: nil, error_message: nil)
    RequestLog.create!(
      user: current_user,
      http_method: request.method,
      path: request.path,
      ollama_model: ollama_model,
      server_used: server_used,
      response_status: response_status,
      response_time_ms: response_time_ms,
      error_message: error_message
    )
  rescue => e
    Rails.logger.error "Failed to log request: #{e.message}"
  end
end
