Rails.application.routes.draw do
  devise_for :users

  # Health check endpoints (no authentication required)
  get "/health", to: "health#check"
  get "up" => "rails/health#show", as: :rails_health_check

  # Ollama API proxy - catch all routes and forward them
  # This must be last to avoid conflicts with other routes
  match "*path", to: "proxy#forward", via: :all, constraints: lambda { |req|
    # Skip health check and devise routes
    !req.path.start_with?("/health") &&
    !req.path.start_with?("/up") &&
    !req.path.start_with?("/users")
  }

  # Root also goes to proxy for Ollama compatibility
  root to: "proxy#forward"
end
