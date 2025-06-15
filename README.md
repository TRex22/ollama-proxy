# Ollama Proxy Server

A production-ready Ruby on Rails 8.0.2 proxy server for managing multiple Ollama instances with intelligent routing, user authentication via Devise, and comprehensive logging. Built with Ruby 3.4.4.

## Features

- **Intelligent Routing**: Automatically routes requests between multiple GPU servers based on:
  - Dynamic model memory requirements (fetched from Ollama API)
  - Server priority and memory limits configuration
  - Server availability and performance
- **User Authentication**: Devise-based user management with API token authentication
- **External Host Support**: Route specific models to third-party APIs (OpenAI, Anthropic, etc.)
- **Comprehensive Logging**: Request logging with performance metrics stored in configurable directories
- **Health Monitoring**: Built-in health check endpoints for monitoring server status
- **Production Ready**: Designed to run as a systemd service under the ollama user
- **SQLite Database**: Lightweight database for user management and request logging
- **Configurable Memory Limits**: Set maximum memory limits per server with automatic model routing

## Prerequisites

- Ruby 3.4.4
- Rails 8.0.2
- SQLite3
- Two or more Ollama servers running on different ports
- (Optional) systemd for service management

## Installation

1. **Clone the repository:**
   ```bash
   git clone <your-repo-url>
   cd ollama-proxy
   ```

2. **Install Ruby dependencies:**
   ```bash
   bundle install
   ```

3. **Setup database:**
   ```bash
   rails db:create db:migrate
   ```

4. **Create log directories:**
   ```bash
   # For development
   mkdir -p log
   
   # For production
   sudo mkdir -p /var/log/ollama-proxy
   sudo chown ollama:ollama /var/log/ollama-proxy
   ```

5. **Configure your setup:**
   Edit `config/ollama_proxy.yml` to match your server configuration (see Configuration section below).

## Configuration

### Server Configuration

Edit `config/ollama_proxy.yml` to configure your Ollama servers and routing rules:

```yaml
production:
  proxy_port: 11434                    # Port for the proxy server
  
  # Server configuration with priority and memory limits
  servers:
    high_performance:
      host: "localhost"
      port: 11435                      # Port for your high-performance GPUs
      name: "high_performance"
      priority: 1                      # Higher priority = preferred server
      max_memory_gb: null              # null = unlimited memory
      enabled: true
    legacy:
      host: "localhost"
      port: 11436                      # Port for your legacy GPUs
      name: "legacy"
      priority: 2                      # Lower priority = fallback server
      max_memory_gb: 8                 # Only accept models up to 8GB
      enabled: true
  
  # External third-party hosts for specific models
  external_hosts:
    openai:
      host: "api.openai.com"
      port: 443
      protocol: "https"
      api_key_env: "OPENAI_API_KEY"
      name: "openai"
      enabled: false                   # Enable when ready to use
  
  # Model routing configuration
  model_config:
    # Explicit server assignments (overrides automatic routing)
    explicit_assignments:
      "gpt-4": "openai"
      "claude-3-sonnet": "anthropic"
    
    # Memory requirement overrides (in GB) - used when Ollama API doesn't provide size
    memory_overrides:
      "custom-model-70b": 40.0
    
    # Pattern-based memory estimation for unknown models
    memory_patterns:
      - pattern: ".*-7b.*"
        memory_gb: 4.5
      - pattern: ".*-70b.*"
        memory_gb: 40.0
```

### Environment Variables

For external API integration, set these environment variables:

```bash
export OPENAI_API_KEY="your-openai-api-key"
export ANTHROPIC_API_KEY="your-anthropic-api-key"
```

## User Management

### Create a new user:
```bash
rails users:create[username]
```
This will output the user's API token for authentication.

### List all users:
```bash
rails users:list
```

### Deactivate a user:
```bash
rails users:deactivate[username]
```

## Running the Server

### Development:
```bash
rails server
```

### Production:
```bash
RAILS_ENV=production rails server
```

## API Usage

Use the proxy exactly like a regular Ollama server, but include your bearer token:

### Basic Usage:
```bash
curl -H "Authorization: Bearer YOUR_API_TOKEN" \
     -H "Content-Type: application/json" \
     -d '{"model": "llama2", "prompt": "Hello, world!"}' \
     http://localhost:11434/api/generate
```

### List Models:
```bash
curl -H "Authorization: Bearer YOUR_API_TOKEN" \
     http://localhost:11434/api/tags
```

### Health Check (No authentication required):
```bash
curl http://localhost:11434/health
```

## How It Works

### Intelligent Routing

The proxy uses a sophisticated routing algorithm:

1. **Check Explicit Assignments**: If a model is explicitly assigned to a server in config, use that server
2. **Fetch Model Memory Requirements**: Query the Ollama servers' `/api/tags` endpoint to get actual model sizes
3. **Apply Memory Constraints**: Filter servers based on their `max_memory_gb` limits
4. **Priority Selection**: Among valid servers, prefer higher priority servers
5. **Availability Check**: Route to available servers based on response time thresholds
6. **Fallback Logic**: Use pattern-based or default memory estimates if API data unavailable

### External Host Integration

Models can be routed to external APIs like OpenAI or Anthropic by configuring them in the `external_hosts` and `explicit_assignments` sections.

### Caching

Model information is cached to reduce API calls to Ollama servers. Cache TTL is configurable via `cache_ttl_seconds`.

## Running as a Service

### 1. Deploy to production directory:
```bash
sudo cp -r . /opt/ollama-proxy
sudo chown -R ollama:ollama /opt/ollama-proxy
```

### 2. Create systemd service file:
```bash
sudo tee /etc/systemd/system/ollama-proxy.service > /dev/null <<'EOF'
[Unit]
Description=Ollama Proxy Server
After=network.target

[Service]
Type=simple
User=ollama
Group=ollama
WorkingDirectory=/opt/ollama-proxy
ExecStart=/usr/local/bin/bundle exec rails server -e production
Restart=always
RestartSec=10

# Environment variables
Environment=RAILS_ENV=production
Environment=BUNDLE_PATH=/opt/ollama-proxy/vendor/bundle

# Security settings
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/opt/ollama-proxy /var/log/ollama-proxy

[Install]
WantedBy=multi-user.target
EOF
```

### 3. Enable and start service:
```bash
sudo systemctl enable ollama-proxy
sudo systemctl start ollama-proxy
sudo systemctl status ollama-proxy
```

## Testing

Run the test suite:
```bash
rspec
```

## Development

### Code Style:
```bash
bundle exec rubocop
```

### Database Console:
```bash
rails console
```

### Logs:
```bash
# Development
tail -f log/development.log

# Production
tail -f /var/log/ollama-proxy/application.log
```

## Architecture

```
Client Request
     ↓
API Token Authentication (Devise)
     ↓
Proxy Controller
     ↓
Model Memory Analysis
     ↓
Server Selection Algorithm
     ↓
Request Forwarding
     ↓
Response & Logging
```

## Security Features

- **Bearer Token Authentication**: All requests require valid API tokens
- **Constant-time Token Comparison**: Prevents timing attacks
- **User Management**: Enable/disable users as needed
- **Request Logging**: Full audit trail of all requests
- **Secure Headers**: Standard Rails security headers

## Performance Considerations

- **Connection Pooling**: Efficient HTTP connections to backend servers
- **Model Info Caching**: Reduces repeated API calls for model information
- **Async Logging**: Non-blocking request logging
- **Health Check Optimization**: Quick server availability detection

## Troubleshooting

### Common Issues:

1. **Server not responding**: Check if Ollama servers are running on configured ports
2. **Authentication failing**: Verify API token is correctly generated and not expired
3. **Model routing issues**: Check model memory requirements and server limits
4. **Logging issues**: Ensure log directories exist and have proper permissions

### Debug Mode:

Enable debug logging in development:
```yaml
# config/ollama_proxy.yml
development:
  logging:
    level: "debug"
```

## Next Steps

The following components still need to be implemented:
- ApplicationController with authentication
- HealthController for server health checks  
- ProxyController for intelligent request routing
- Routes configuration for proxy forwarding
- User management rake tasks
- Puma configuration for production deployment
- RSpec test suite
- RuboCop configuration

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests
5. Run the test suite
6. Submit a pull request

## License

[Your License Here]

## Support

For issues and feature requests, please use the GitHub issue tracker.
