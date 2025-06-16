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

## File Locations on Target Server

- Ollama configs: `/etc/systemd/system/ollama-*.service`
- Ollama data: `/var/lib/ollama/`
- Application logs: `/var/log/ollama-proxy/`
- Backups: `/opt/ollama-proxy-backup/YYYYMMDD_HHMMSS/`