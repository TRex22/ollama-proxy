require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module OllamaProxy
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.0

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    # Only loads a smaller set of middleware suitable for API only apps.
    # Middleware like session, flash, cookies can be added back manually.
    # Skip views, helpers and assets when generating a new resource.
    config.api_only = true

    # Load custom configuration
    config.ollama_proxy = config_for(:ollama_proxy)

    # Configure logging for production deployment
    if Rails.env.production?
      log_config = config.ollama_proxy[:logging]
      if log_config[:enabled]
        log_dir = log_config[:directory]
        FileUtils.mkdir_p(log_dir) unless Dir.exist?(log_dir)
        
        config.logger = Logger.new(
          File.join(log_dir, 'application.log'),
          'daily',
          log_config[:max_files] || 10
        )
        config.logger.level = Logger.const_get(log_config[:level].upcase)
      end
    end

    # Set time zone
    config.time_zone = 'UTC'
  end
end
