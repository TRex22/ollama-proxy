#!/bin/bash
set -e

# Ollama Multi-Instance Setup Script for Kamal Deployment
# This script configures multiple Ollama instances with CUDA device splitting

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="/opt/ollama-proxy-backup/$(date +%Y%m%d_%H%M%S)"
OLLAMA_CONFIG_DIR="/etc/systemd/system"
OLLAMA_DATA_DIR="/var/lib/ollama"

# Colors for output (silent mode compatible)
if [[ "${SILENT:-0}" != "1" ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    NC='\033[0m'
else
    RED='' GREEN='' YELLOW='' BLUE='' NC=''
fi

log() {
    [[ "${SILENT:-0}" != "1" ]] && echo -e "${1}"
}

error() {
    echo -e "${RED}ERROR: ${1}${NC}" >&2
    exit 1
}

warn() {
    echo -e "${YELLOW}WARNING: ${1}${NC}" >&2
}

success() {
    log "${GREEN}✓ ${1}${NC}"
}

info() {
    log "${BLUE}ℹ ${1}${NC}"
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root"
    fi
}

# Detect available CUDA devices
detect_cuda_devices() {
    if command -v nvidia-smi >/dev/null 2>&1; then
        CUDA_DEVICES=$(nvidia-smi --query-gpu=index --format=csv,noheader,nounits | wc -l)
        info "Detected ${CUDA_DEVICES} CUDA devices"
        return 0
    else
        warn "nvidia-smi not found. Proceeding without CUDA device detection."
        CUDA_DEVICES=0
        return 1
    fi
}

# Check existing Ollama installation
check_existing_ollama() {
    local has_ollama=0
    local has_service=0
    
    if command -v ollama >/dev/null 2>&1; then
        has_ollama=1
        info "Existing Ollama installation found"
    fi
    
    if systemctl is-enabled ollama >/dev/null 2>&1; then
        has_service=1
        info "Existing Ollama service found"
    fi
    
    if [[ $has_ollama -eq 1 || $has_service -eq 1 ]]; then
        return 0
    else
        return 1
    fi
}

# Backup existing configuration
backup_config() {
    info "Creating backup in ${BACKUP_DIR}"
    mkdir -p "${BACKUP_DIR}"
    
    # Backup systemd services
    if [[ -f "${OLLAMA_CONFIG_DIR}/ollama.service" ]]; then
        cp "${OLLAMA_CONFIG_DIR}/ollama.service" "${BACKUP_DIR}/"
        success "Backed up ollama.service"
    fi
    
    # Backup any existing multi-instance services
    for service in "${OLLAMA_CONFIG_DIR}"/ollama-*.service; do
        if [[ -f "$service" ]]; then
            cp "$service" "${BACKUP_DIR}/"
            success "Backed up $(basename "$service")"
        fi
    done
    
    # Backup data directory if it exists
    if [[ -d "${OLLAMA_DATA_DIR}" ]]; then
        cp -r "${OLLAMA_DATA_DIR}" "${BACKUP_DIR}/ollama-data"
        success "Backed up Ollama data directory"
    fi
}

# Prompt for override confirmation
prompt_override() {
    if [[ "${FORCE_OVERRIDE:-0}" == "1" ]]; then
        return 0
    fi
    
    echo
    warn "Existing Ollama configuration detected!"
    echo "This will:"
    echo "  - Stop the current Ollama service"
    echo "  - Create backup in ${BACKUP_DIR}"
    echo "  - Configure multiple Ollama instances with CUDA device splitting"
    echo "  - Update systemd services"
    echo
    
    read -p "Do you want to proceed? (y/N): " -n 1 -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        info "Operation cancelled by user"
        exit 0
    fi
}

# Stop existing Ollama services
stop_existing_services() {
    info "Stopping existing Ollama services"
    
    # Stop main service
    if systemctl is-active ollama >/dev/null 2>&1; then
        systemctl stop ollama
        success "Stopped ollama service"
    fi
    
    # Stop any multi-instance services
    for service in ollama-gpu0 ollama-gpu1; do
        if systemctl is-active "$service" >/dev/null 2>&1; then
            systemctl stop "$service"
            success "Stopped $service service"
        fi
    done
}

# Create systemd service for Ollama instance
create_ollama_service() {
    local instance_name="$1"
    local port="$2"
    local cuda_devices="$3"
    local service_file="${OLLAMA_CONFIG_DIR}/${instance_name}.service"
    
    info "Creating ${instance_name} service on port ${port}"
    
    cat > "${service_file}" << EOF
[Unit]
Description=Ollama ${instance_name} Server
After=network-online.target
Wants=network-online.target

[Service]
Type=exec
ExecStart=/usr/local/bin/ollama serve
Environment="OLLAMA_HOST=0.0.0.0:${port}"
Environment="OLLAMA_MODELS=${OLLAMA_DATA_DIR}/${instance_name}/models"
$([ -n "$cuda_devices" ] && echo "Environment=\"CUDA_VISIBLE_DEVICES=${cuda_devices}\"")
User=ollama
Group=ollama
Restart=always
RestartSec=3
StandardOutput=journal
StandardError=journal
SyslogIdentifier=${instance_name}

[Install]
WantedBy=multi-user.target
EOF
    
    # Create data directory
    mkdir -p "${OLLAMA_DATA_DIR}/${instance_name}/models"
    chown -R ollama:ollama "${OLLAMA_DATA_DIR}/${instance_name}"
    
    success "Created ${instance_name} service"
}

# Setup multiple Ollama instances
setup_multi_instance() {
    local num_instances=2
    local base_port=11435
    
    info "Setting up ${num_instances} Ollama instances"
    
    # Create ollama user if not exists
    if ! id -u ollama >/dev/null 2>&1; then
        useradd -r -s /bin/false -m -d /var/lib/ollama ollama
        success "Created ollama user"
    fi
    
    # Setup instances based on CUDA devices
    if [[ $CUDA_DEVICES -gt 0 ]]; then
        if [[ $CUDA_DEVICES -eq 1 ]]; then
            # Single GPU - create two instances sharing the device
            create_ollama_service "ollama-gpu0" "$((base_port))" "0"
            create_ollama_service "ollama-gpu1" "$((base_port + 1))" "0"
        else
            # Multiple GPUs - split devices
            local devices_per_instance=$((CUDA_DEVICES / 2))
            local gpu0_devices=$(seq -s, 0 $((devices_per_instance - 1)))
            local gpu1_devices=$(seq -s, $devices_per_instance $((CUDA_DEVICES - 1)))
            
            create_ollama_service "ollama-gpu0" "$((base_port))" "$gpu0_devices"
            create_ollama_service "ollama-gpu1" "$((base_port + 1))" "$gpu1_devices"
        fi
    else
        # CPU-only instances
        create_ollama_service "ollama-cpu0" "$((base_port))" ""
        create_ollama_service "ollama-cpu1" "$((base_port + 1))" ""
    fi
}

# Enable and start services
start_services() {
    info "Enabling and starting Ollama services"
    
    systemctl daemon-reload
    
    for service in ollama-gpu0 ollama-gpu1 ollama-cpu0 ollama-cpu1; do
        if [[ -f "${OLLAMA_CONFIG_DIR}/${service}.service" ]]; then
            systemctl enable "${service}" >/dev/null 2>&1
            systemctl start "${service}"
            success "Started ${service}"
        fi
    done
}

# Verify services are running
verify_services() {
    info "Verifying services are running"
    
    local all_running=1
    for port in 11435 11436; do
        if curl -s "http://localhost:${port}" >/dev/null 2>&1; then
            success "Ollama instance on port ${port} is responding"
        else
            warn "Ollama instance on port ${port} is not responding"
            all_running=0
        fi
    done
    
    if [[ $all_running -eq 1 ]]; then
        success "All Ollama instances are running successfully"
    else
        warn "Some Ollama instances may not be running properly"
    fi
}

# Update firewall if needed
update_firewall() {
    if command -v ufw >/dev/null 2>&1; then
        info "Updating UFW firewall rules"
        ufw allow 11435/tcp >/dev/null 2>&1
        ufw allow 11436/tcp >/dev/null 2>&1
        success "Updated firewall rules"
    elif command -v firewall-cmd >/dev/null 2>&1; then
        info "Updating firewalld rules"
        firewall-cmd --permanent --add-port=11435/tcp >/dev/null 2>&1
        firewall-cmd --permanent --add-port=11436/tcp >/dev/null 2>&1
        firewall-cmd --reload >/dev/null 2>&1
        success "Updated firewall rules"
    fi
}

# Create Docker network for Ollama
create_docker_network() {
    if command -v docker >/dev/null 2>&1; then
        if ! docker network ls | grep -q ollama-network; then
            docker network create ollama-network >/dev/null 2>&1
            success "Created Docker network: ollama-network"
        else
            info "Docker network ollama-network already exists"
        fi
    fi
}

# Main execution
main() {
    info "Starting Ollama multi-instance setup"
    
    check_root
    detect_cuda_devices
    
    if check_existing_ollama; then
        prompt_override
        backup_config
        stop_existing_services
    fi
    
    setup_multi_instance
    start_services
    update_firewall
    create_docker_network
    
    sleep 5
    verify_services
    
    success "Ollama multi-instance setup completed successfully"
    info "High-performance server: http://localhost:11435"
    info "Legacy server: http://localhost:11436"
    info "Backup created at: ${BACKUP_DIR}"
}

# Run main function
main "$@"