FactoryBot.define do
  factory :request_log do
    association :user
    http_method { "GET" }
    path { "/api/tags" }
    ollama_model { "llama2" }
    server_used { "high_performance" }
    response_status { 200 }
    response_time_ms { 150.5 }
    error_message { nil }
  end
end
