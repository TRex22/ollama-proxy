# Kamal Deployment Guide

This guide covers deploying the Ollama Proxy to a remote server using Kamal.

## Prerequisites

- Docker installed on target server
- Existing Ollama installation (optional - will be configured automatically)
- SSH access to target server
- Kamal gem installed locally (`gem install kamal`)

## Environment Variables

Set these environment variables before deployment:

```bash
# Required: Target server IP or hostname
export DEPLOY_HOST=your.server.ip.address

# Required: Rails application secrets
export SECRET_KEY_BASE=$(bin/rails secret)

# Optional: Force override existing Ollama config (default: prompt user)
export FORCE_OVERRIDE=0

# Optional: Silent deployment (reduces output, default: 0)
export SILENT=0
```

## Deployment Steps

1. **Set environment variables:**
   ```bash
   export DEPLOY_HOST=192.168.1.100
   export SECRET_KEY_BASE=$(bin/rails secret)
   ```

2. **Initial deployment:**
   ```bash
   kamal deploy
   ```

3. **Subsequent deployments:**
   ```bash
   kamal deploy
   ```

## Ollama Configuration

The deployment automatically:
- Detects existing Ollama installations
- Creates backups of existing configurations
- Prompts for override confirmation (unless `FORCE_OVERRIDE=1`)
- Configures multiple Ollama instances with CUDA device splitting
- Sets up systemd services for high availability

### Ollama Instances

Two instances are created:
- **High-performance server**: `http://localhost:11435` (GPU 0 or first half of GPUs)
- **Legacy server**: `http://localhost:11436` (GPU 0 or second half of GPUs)

### CUDA Device Splitting

- **Single GPU**: Both instances share GPU 0
- **Multiple GPUs**: Devices split between instances
- **No GPU**: CPU-only instances created

## Kamal Commands

```bash
# Deploy application
kamal deploy

# Check deployment status
kamal app details

# View logs
kamal app logs

# Access Rails console
kamal app exec -i "bin/rails console"

# SSH into server
kamal app exec -i bash

# Rollback deployment
kamal app rollback

# Remove deployment
kamal app remove
```

## Troubleshooting

### Ollama Setup Issues

If Ollama setup fails, you can:

1. Check service status:
   ```bash
   ssh user@$DEPLOY_HOST "sudo systemctl status ollama-gpu0 ollama-gpu1"
   ```

2. Manually run setup:
   ```bash
   ssh user@$DEPLOY_HOST "sudo /opt/kamal/ollama-proxy/scripts/setup-ollama.sh"
   ```

3. View setup logs:
   ```bash
   ssh user@$DEPLOY_HOST "sudo journalctl -u ollama-gpu0 -f"
   ```

### Application Issues

1. Check application logs:
   ```bash
   kamal app logs
   ```

2. Verify health endpoint:
   ```bash
   curl http://$DEPLOY_HOST:3000/health
   ```

3. Check container status:
   ```bash
   kamal app details
   ```

## Security Notes

- Never commit secrets to git
- Use environment variables for all sensitive data
- The deployment creates backups before modifying Ollama configs
- Firewall rules are automatically updated for Ollama ports (11435, 11436)

## Local Development Setup (Mac)

For local development with multiple Ollama servers, create your own configuration files that won't be committed to the repository.

### 1. Setup Environment Variables

Copy the example environment file:
```bash
cp .env.local.example .env.local
```

Edit `.env.local` with your actual server details:
```bash
# High-performance server (remote GPU server)
OLLAMA_HIGH_PERF_HOST=192.168.1.100
OLLAMA_HIGH_PERF_PORT=11434

# Low-performance server (remote CPU server)
OLLAMA_LOW_PERF_HOST=192.168.1.101  
OLLAMA_LOW_PERF_PORT=11434

# Generate secret: bin/rails secret
SECRET_KEY_BASE=your_generated_secret_key_base_here
```

### 2. Configure Local Ollama (Homebrew)

Configure your local Ollama to run on port 11435:
```bash
# Stop existing Ollama service
brew services stop ollama

# Create custom Ollama service for port 11435
mkdir -p ~/Library/LaunchAgents

cat > ~/Library/LaunchAgents/homebrew.mxcl.ollama-custom.plist << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>homebrew.mxcl.ollama-custom</string>
    <key>ProgramArguments</key>
    <array>
        <string>/opt/homebrew/bin/ollama</string>
        <string>serve</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>EnvironmentVariables</key>
    <dict>
        <key>OLLAMA_HOST</key>
        <string>127.0.0.1:11435</string>
    </dict>
</dict>
</plist>
EOF

# Start custom Ollama service
launchctl load ~/Library/LaunchAgents/homebrew.mxcl.ollama-custom.plist
launchctl start homebrew.mxcl.ollama-custom
```

### 3. Create Local Configuration

Create your local Ollama proxy configuration:
```bash
cat > config/ollama_proxy.local.yml << 'EOF'
development:
  proxy_port: 11434
  
  servers:
    high_performance:
      host: "<%= ENV['OLLAMA_HIGH_PERF_HOST'] %>"
      port: <%= ENV['OLLAMA_HIGH_PERF_PORT'] %>
      name: "high_performance"
      priority: 1
      max_memory_gb: null  # Unlimited
      enabled: true
    medium_performance:
      host: "localhost"
      port: 11435
      name: "medium_performance" 
      priority: 2
      max_memory_gb: 10  # Up to 10GB models
      enabled: true
    low_performance:
      host: "<%= ENV['OLLAMA_LOW_PERF_HOST'] %>"
      port: <%= ENV['OLLAMA_LOW_PERF_PORT'] %>
      name: "low_performance"
      priority: 3
      max_memory_gb: 6  # Up to 6GB models
      enabled: true
  
  logging:
    enabled: true
    level: "debug"
    directory: "./log"
    max_size: "10MB"
    max_files: 3
EOF
```

### 4. Run Locally

Start the application using your local configuration:
```bash
# Load environment variables
source .env.local

# Start the Rails server with custom config
OLLAMA_PROXY_CONFIG=config/ollama_proxy.local.yml rails server
```

### 5. Local Kamal Deployment (Optional)

For local containerized deployment:
```bash
# Create local Kamal secrets
cat > .kamal/secrets.local << 'EOF'
RAILS_MASTER_KEY=$(cat config/master.key)
SECRET_KEY_BASE=$SECRET_KEY_BASE
OLLAMA_HIGH_PERF_HOST=$OLLAMA_HIGH_PERF_HOST
OLLAMA_HIGH_PERF_PORT=$OLLAMA_HIGH_PERF_PORT
OLLAMA_LOW_PERF_HOST=$OLLAMA_LOW_PERF_HOST
OLLAMA_LOW_PERF_PORT=$OLLAMA_LOW_PERF_PORT
EOF

# Deploy locally with Kamal
KAMAL_SECRETS=.kamal/secrets.local kamal deploy -c config/deploy.local.yml
```

### Verification

Test your setup:
```bash
# Check high-performance server
curl http://$OLLAMA_HIGH_PERF_HOST:$OLLAMA_HIGH_PERF_PORT/

# Check local medium-performance server  
curl http://localhost:11435/

# Check low-performance server
curl http://$OLLAMA_LOW_PERF_HOST:$OLLAMA_LOW_PERF_PORT/

# Test the proxy
curl http://localhost:3000/health
```

## File Locations on Target Server

- Ollama configs: `/etc/systemd/system/ollama-*.service`
- Ollama data: `/var/lib/ollama/`
- Application logs: `/var/log/ollama-proxy/`
- Backups: `/opt/ollama-proxy-backup/YYYYMMDD_HHMMSS/`