class RequestLog < ApplicationRecord
  belongs_to :user

  validates :http_method, :path, presence: true

  scope :recent, -> { order(created_at: :desc) }
  scope :errors, -> { where("response_status >= 400 OR error_message IS NOT NULL") }
  scope :for_model, ->(model_name) { where(ollama_model: model_name) }
  scope :for_server, ->(server_name) { where(server_used: server_name) }
end
