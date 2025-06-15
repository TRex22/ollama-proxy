# Ollama Proxy Puma Configuration
# Optimized for proxying requests to Ollama servers

# Thread configuration
# Increase threads for better I/O handling since we're proxying requests
max_threads_count = ENV.fetch("RAILS_MAX_THREADS") { 10 }
min_threads_count = ENV.fetch("RAILS_MIN_THREADS") { max_threads_count }
threads min_threads_count, max_threads_count

# Port configuration
# Use ollama_proxy config port or fall back to environment/default
if defined?(Rails) && Rails.application.config.respond_to?(:ollama_proxy)
  default_port = Rails.application.config.ollama_proxy[:proxy_port] rescue 11434
else
  default_port = 11434
end
port ENV.fetch("PORT") { default_port }

# Worker timeout - increase for long-running model inference requests
worker_timeout ENV.fetch("WORKER_TIMEOUT") { 3600 }

# Environment
environment ENV.fetch("RAILS_ENV") { "development" }

# PID file
pidfile ENV.fetch("PIDFILE") { "tmp/pids/server.pid" }

# Allow puma to be restarted by `bin/rails restart` command.
plugin :tmp_restart

# Run the Solid Queue supervisor inside of Puma for single-server deployments
plugin :solid_queue if ENV["SOLID_QUEUE_IN_PUMA"]

# Production-specific configuration
if ENV["RAILS_ENV"] == "production"
  # Workers for production (optional - single worker works well for proxy)
  workers ENV.fetch("WEB_CONCURRENCY") { 1 }
  
  # Run as ollama user in production
  user "ollama", "ollama" if Process.uid == 0
  
  # Preload the application for better performance with multiple workers
  preload_app! if ENV.fetch("WEB_CONCURRENCY") { 1 }.to_i > 1
  
  # Set up proper logging in production
  if Rails.application.config.ollama_proxy[:logging][:enabled]
    log_dir = Rails.application.config.ollama_proxy[:logging][:directory]
    FileUtils.mkdir_p(log_dir) unless Dir.exist?(log_dir)
    stdout_redirect File.join(log_dir, 'puma.log'), File.join(log_dir, 'puma.log'), true
  end
  
  # Handle worker forking
  on_worker_boot do
    # Reconnect Active Record after fork
    ActiveRecord::Base.establish_connection if defined?(ActiveRecord)
  end
  
  # Clean shutdown
  on_worker_shutdown do
    # Cleanup code if needed
  end
  
  # Bind to all interfaces in production
  bind "tcp://0.0.0.0:#{ENV.fetch('PORT') { default_port }}"
else
  # Development configuration
  # Bind to localhost only in development
  bind "tcp://127.0.0.1:#{ENV.fetch('PORT') { default_port }}"
end

# SSL configuration (uncomment and configure if needed)
# ssl_bind "0.0.0.0", "11435", {
#   key: "/path/to/server.key",
#   cert: "/path/to/server.crt"
# }
