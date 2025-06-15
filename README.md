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

## Quick Start - Production Setup

For a complete Linux server setup with auto-starting services, see the [Production Quick Start](#production-quick-start---linux-server) section below.

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

## Production Quick Start - Linux Server

Complete setup guide for a production Linux server with auto-starting Ollama servers and proxy.

### Prerequisites Installation

```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install required packages
sudo apt install -y curl git build-essential sqlite3 libsqlite3-dev

# Install Ruby 3.4.4 (using rbenv)
curl -fsSL https://github.com/rbenv/rbenv-installer/raw/HEAD/bin/rbenv-installer | bash
echo 'export PATH="$HOME/.rbenv/bin:$PATH"' >> ~/.bashrc
echo 'eval "$(rbenv init -)"' >> ~/.bashrc
source ~/.bashrc
rbenv install 3.4.4
rbenv global 3.4.4

# Install Bundler
gem install bundler

# Install Ollama
curl -fsSL https://ollama.ai/install.sh | sh
```

### 1. Create ollama user and setup directories

```bash
# Create ollama user if it doesn't exist
sudo useradd -r -s /bin/bash -m -d /home/ollama ollama

# Create necessary directories
sudo mkdir -p /opt/ollama-proxy
sudo mkdir -p /var/log/ollama-proxy
sudo chown -R ollama:ollama /var/log/ollama-proxy
sudo chmod 755 /var/log/ollama-proxy
```

### 2. Setup Ollama servers

```bash
# Create systemd service for high-performance Ollama server
sudo tee /etc/systemd/system/ollama-high-performance.service > /dev/null <<'EOF'
[Unit]
Description=Ollama High Performance Server
After=network.target

[Service]
Type=simple
User=ollama
Group=ollama
Environment="OLLAMA_HOST=0.0.0.0:11435"
Environment="CUDA_VISIBLE_DEVICES=0,1"
ExecStart=/usr/local/bin/ollama serve
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

# Create systemd service for legacy Ollama server  
sudo tee /etc/systemd/system/ollama-legacy.service > /dev/null <<'EOF'
[Unit]
Description=Ollama Legacy Server
After=network.target

[Service]
Type=simple
User=ollama
Group=ollama
Environment="OLLAMA_HOST=0.0.0.0:11436"
Environment="CUDA_VISIBLE_DEVICES=2,3"
ExecStart=/usr/local/bin/ollama serve
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
```

### 3. Deploy the proxy application

```bash
# Clone and setup the application
cd /tmp
git clone <your-repo-url> ollama-proxy
sudo cp -r ollama-proxy /opt/
sudo chown -R ollama:ollama /opt/ollama-proxy

# Switch to ollama user for setup
sudo -u ollama -H bash << 'EOSCRIPT'
cd /opt/ollama-proxy

# Install Ruby dependencies
bundle install --deployment --without development test

# Setup database
RAILS_ENV=production bundle exec rails db:create db:migrate

# Generate new Rails secret key
RAILS_ENV=production bundle exec rails credentials:edit

# Create initial admin user
RAILS_ENV=production bundle exec rails users:create[admin]
EOSCRIPT
```

### 4. Configure the proxy

```bash
# Edit configuration for your setup
sudo -u ollama nano /opt/ollama-proxy/config/ollama_proxy.yml

# Example configuration for the setup above:
cat > /tmp/ollama_proxy_production.yml << 'EOF'
production:
  proxy_port: 11434
  servers:
    high_performance:
      host: "localhost"
      port: 11435
      name: "high_performance"
      priority: 1
      max_memory_gb: null
      enabled: true
    legacy:
      host: "localhost"
      port: 11436
      name: "legacy"
      priority: 2
      max_memory_gb: 8
      enabled: true
  model_config:
    memory_patterns:
      - pattern: ".*-7b.*"
        memory_gb: 4.5
      - pattern: ".*-13b.*"
        memory_gb: 8.0
      - pattern: ".*-70b.*"
        memory_gb: 40.0
    default_memory_gb: 4.5
    cache_model_info: true
    cache_ttl_seconds: 3600
  request_timeout: 300
  logging:
    enabled: true
    level: "info"
    directory: "/var/log/ollama-proxy"
    max_size: "100MB"
    max_files: 10
EOF

sudo cp /tmp/ollama_proxy_production.yml /opt/ollama-proxy/config/ollama_proxy.yml
sudo chown ollama:ollama /opt/ollama-proxy/config/ollama_proxy.yml
```

### 5. Install and start all services

```bash
# Install Ollama proxy service
sudo cp /opt/ollama-proxy/docs/ollama-proxy.service /etc/systemd/system/

# Reload systemd and enable all services
sudo systemctl daemon-reload

# Enable and start Ollama servers
sudo systemctl enable ollama-high-performance
sudo systemctl enable ollama-legacy
sudo systemctl start ollama-high-performance
sudo systemctl start ollama-legacy

# Enable and start proxy
sudo systemctl enable ollama-proxy
sudo systemctl start ollama-proxy

# Check status
sudo systemctl status ollama-high-performance
sudo systemctl status ollama-legacy
sudo systemctl status ollama-proxy
```

### 6. Verify installation

```bash
# Check proxy health
curl http://localhost:11434/health | jq

# Pull some models (this may take a while)
sudo -u ollama ollama pull llama2:7b
sudo -u ollama ollama pull mistral:7b

# Test the proxy with your admin token
curl -H "Authorization: Bearer YOUR_ADMIN_TOKEN" \
     -H "Content-Type: application/json" \
     -d '{"model": "llama2:7b", "prompt": "Hello from the proxy!"}' \
     http://localhost:11434/api/generate
```

### 7. Firewall setup (optional)

```bash
# If using UFW firewall
sudo ufw allow 11434/tcp comment "Ollama Proxy"

# Block direct access to backend servers (optional)
# sudo ufw deny 11435/tcp
# sudo ufw deny 11436/tcp
```

### 8. Setup logrotate (optional)

```bash
sudo tee /etc/logrotate.d/ollama-proxy > /dev/null << 'EOF'
/var/log/ollama-proxy/*.log {
    daily
    missingok
    rotate 30
    compress
    delaycompress
    notifempty
    create 644 ollama ollama
    postrotate
        systemctl reload ollama-proxy
    endscript
}
EOF
```

### Service Management Commands

```bash
# Check all services
sudo systemctl status ollama-high-performance ollama-legacy ollama-proxy

# Restart proxy after configuration changes
sudo systemctl restart ollama-proxy

# View logs
sudo journalctl -u ollama-proxy -f
tail -f /var/log/ollama-proxy/application.log

# Create additional users
sudo -u ollama RAILS_ENV=production bundle exec rails users:create[username] -C /opt/ollama-proxy

# Monitor server health
watch -n 5 'curl -s http://localhost:11434/health | jq'
```

### GPU Configuration Notes

- **CUDA_VISIBLE_DEVICES**: Adjust GPU assignments based on your hardware
- **High-performance server**: Uses GPUs 0,1 (typically newer/faster GPUs)  
- **Legacy server**: Uses GPUs 2,3 (typically older/slower GPUs)
- **Memory limits**: Configure `max_memory_gb` based on GPU VRAM
- **Model placement**: Large models automatically route to high-performance server

This setup provides a production-ready Ollama proxy with automatic startup, logging, and intelligent model routing across multiple GPU configurations.

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
