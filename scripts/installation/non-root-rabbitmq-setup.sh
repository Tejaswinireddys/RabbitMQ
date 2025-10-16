#!/bin/bash

# RabbitMQ 4.1.x Non-Root Installation and Management Script
# This script provides minimal sudo privileges for RabbitMQ cluster management
# Version: 1.0
# Target: RHEL 8.x with non-root user deployment

set -e

# Configuration
RABBITMQ_USER="rabbitmq-admin"
RABBITMQ_HOME="/home/$RABBITMQ_USER"
DEPLOYMENT_DIR="$RABBITMQ_HOME/rabbitmq-deployment"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as non-root user
check_user() {
    if [[ $EUID -eq 0 ]]; then
        error "This script must be run as a non-root user"
        exit 1
    fi
    
    if [[ "$(whoami)" != "$RABBITMQ_USER" ]]; then
        warn "This script is designed for user: $RABBITMQ_USER"
        read -p "Continue anyway? (y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
}

# Create directory structure
create_directories() {
    log "Creating directory structure..."
    
    mkdir -p "$DEPLOYMENT_DIR"/{config,scripts,logs,data,ssl,backup,monitoring}
    mkdir -p "$DEPLOYMENT_DIR"/systemd-override
    mkdir -p "$DEPLOYMENT_DIR"/templates
    
    # Set permissions
    chmod 755 "$DEPLOYMENT_DIR"
    chmod 755 "$DEPLOYMENT_DIR"/*
    
    log "Directory structure created at: $DEPLOYMENT_DIR"
}

# Create sudoers configuration
create_sudoers_config() {
    log "Creating sudoers configuration for minimal privileges..."
    
    cat > "$DEPLOYMENT_DIR/sudoers-rabbitmq.conf" << 'EOF'
# RabbitMQ Non-Root User Sudoers Configuration
# This file should be copied to /etc/sudoers.d/rabbitmq-deployment by system administrator

# User alias for RabbitMQ admin
User_Alias RABBITMQ_ADMINS = rabbitmq-admin

# Command aliases for RabbitMQ operations
Cmnd_Alias RABBITMQ_INSTALL = /usr/bin/dnf install *, /usr/bin/rpm --import *, /usr/bin/tee /etc/yum.repos.d/*
Cmnd_Alias RABBITMQ_SERVICE = /usr/bin/systemctl * rabbitmq-server, /usr/sbin/rabbitmqctl *, /usr/sbin/rabbitmq-plugins *
Cmnd_Alias RABBITMQ_CONFIG = /usr/bin/tee /etc/rabbitmq/*, /usr/bin/mkdir -p /etc/rabbitmq/*, /usr/bin/chown *, /usr/bin/chmod *
Cmnd_Alias RABBITMQ_FIREWALL = /usr/bin/firewall-cmd *
Cmnd_Alias RABBITMQ_SYSCTL = /usr/sbin/sysctl *, /usr/bin/tee /etc/sysctl.d/*, /usr/bin/tee /etc/systemd/system/*
Cmnd_Alias RABBITMQ_LIMITS = /usr/bin/tee /etc/security/limits.d/*, /usr/bin/tee -a /etc/security/limits.conf
Cmnd_Alias RABBITMQ_HOSTS = /usr/bin/tee -a /etc/hosts, /usr/bin/hostnamectl set-hostname *
Cmnd_Alias RABBITMQ_PROCESS = /usr/bin/pkill -f rabbitmq, /usr/bin/ps aux | grep rabbitmq

# Grant permissions
RABBITMQ_ADMINS ALL=(ALL) NOPASSWD: RABBITMQ_INSTALL, RABBITMQ_SERVICE, RABBITMQ_CONFIG, RABBITMQ_FIREWALL, RABBITMQ_SYSCTL, RABBITMQ_LIMITS, RABBITMQ_HOSTS, RABBITMQ_PROCESS
EOF

    log "Sudoers configuration created: $DEPLOYMENT_DIR/sudoers-rabbitmq.conf"
    warn "Please ask your system administrator to copy this file to /etc/sudoers.d/rabbitmq-deployment"
}

# Create system preparation script
create_system_prep_script() {
    log "Creating system preparation script..."
    
    cat > "$DEPLOYMENT_DIR/scripts/01-system-preparation.sh" << 'EOF'
#!/bin/bash
# System Preparation Script for Non-Root RabbitMQ Installation

set -e

echo "=== RabbitMQ System Preparation (Non-Root) ==="

# Update system (requires sudo)
echo "Updating system packages..."
sudo dnf update -y

# Install EPEL repository
echo "Installing EPEL repository..."
sudo dnf install -y epel-release

# Install required packages
echo "Installing required packages..."
sudo dnf install -y curl wget gnupg2 socat logrotate erlang

# Verify Erlang installation
echo "Verifying Erlang installation..."
erl -version

echo "System preparation completed!"
EOF

    chmod +x "$DEPLOYMENT_DIR/scripts/01-system-preparation.sh"
}

# Create repository setup script
create_repo_script() {
    log "Creating repository setup script..."
    
    cat > "$DEPLOYMENT_DIR/scripts/02-repo-setup.sh" << 'EOF'
#!/bin/bash
# Repository Setup Script for Non-Root RabbitMQ Installation

set -e

echo "=== RabbitMQ Repository Setup (Non-Root) ==="

# Create RabbitMQ repository configuration
echo "Configuring RabbitMQ repository..."
sudo tee /etc/yum.repos.d/rabbitmq.repo << 'EOF'
[rabbitmq-server]
name=rabbitmq-server
baseurl=https://packagecloud.io/rabbitmq/rabbitmq-server/el/8/$basearch
repo_gpgcheck=1
gpgcheck=1
enabled=1
gpgkey=https://github.com/rabbitmq/signing-keys/releases/download/3.0/cloudsmith.rabbitmq-server.9F4587F226208342.key
sslverify=1
sslcacert=/etc/pki/tls/certs/ca-bundle.crt
metadata_expire=300
EOF

# Import GPG keys
echo "Importing GPG keys..."
sudo rpm --import https://github.com/rabbitmq/signing-keys/releases/download/3.0/cloudsmith.rabbitmq-server.9F4587F226208342.key

echo "Repository setup completed!"
EOF

    chmod +x "$DEPLOYMENT_DIR/scripts/02-repo-setup.sh"
}

# Create installation script
create_install_script() {
    log "Creating RabbitMQ installation script..."
    
    cat > "$DEPLOYMENT_DIR/scripts/03-rabbitmq-install.sh" << 'EOF'
#!/bin/bash
# RabbitMQ Installation Script for Non-Root User

set -e

echo "=== RabbitMQ Installation (Non-Root) ==="

# Update package cache
echo "Updating package cache..."
sudo dnf update -y

# Install RabbitMQ
echo "Installing RabbitMQ 4.1.x..."
sudo dnf install -y rabbitmq-server

# Verify installation
echo "Verifying RabbitMQ installation..."
rpm -qa | grep rabbitmq

# Create necessary directories
echo "Creating RabbitMQ directories..."
sudo mkdir -p /etc/rabbitmq /var/log/rabbitmq /var/lib/rabbitmq

# Set proper ownership
sudo chown -R rabbitmq:rabbitmq /etc/rabbitmq /var/log/rabbitmq /var/lib/rabbitmq

echo "RabbitMQ installation completed!"
EOF

    chmod +x "$DEPLOYMENT_DIR/scripts/03-rabbitmq-install.sh"
}

# Create system limits script
create_limits_script() {
    log "Creating system limits configuration script..."
    
    cat > "$DEPLOYMENT_DIR/scripts/04-system-limits.sh" << 'EOF'
#!/bin/bash
# System Limits Configuration Script for Non-Root RabbitMQ

set -e

echo "=== Configuring System Limits (Non-Root) ==="

# Create systemd override directory
echo "Creating systemd override configuration..."
sudo mkdir -p /etc/systemd/system/rabbitmq-server.service.d/

# Configure service limits
sudo tee /etc/systemd/system/rabbitmq-server.service.d/limits.conf << 'EOF'
[Service]
LimitNOFILE=300000
LimitNPROC=300000
User=rabbitmq
Group=rabbitmq
EOF

# Configure system-wide limits
echo "Configuring system-wide limits..."
sudo tee /etc/security/limits.d/99-rabbitmq.conf << 'EOF'
# RabbitMQ limits
*               soft    nofile          65536
*               hard    nofile          65536
*               soft    nproc           32768
*               hard    nproc           32768
rabbitmq        soft    nofile          300000
rabbitmq        hard    nofile          300000
rabbitmq        soft    nproc           300000
rabbitmq        hard    nproc           300000
EOF

# Reload systemd
sudo systemctl daemon-reload

echo "System limits configuration completed!"
EOF

    chmod +x "$DEPLOYMENT_DIR/scripts/04-system-limits.sh"
}

# Create kernel parameters script
create_kernel_script() {
    log "Creating kernel parameters configuration script..."
    
    cat > "$DEPLOYMENT_DIR/scripts/05-kernel-params.sh" << 'EOF'
#!/bin/bash
# Kernel Parameters Configuration Script for Non-Root RabbitMQ

set -e

echo "=== Configuring Kernel Parameters (Non-Root) ==="

# Determine environment (QA or Production)
read -p "Environment (qa/prod): " ENV

if [[ "$ENV" == "prod" ]]; then
    echo "Configuring production kernel parameters..."
    sudo tee /etc/sysctl.d/99-rabbitmq.conf << 'EOF'
# Production RabbitMQ kernel parameters
net.core.somaxconn = 8192
net.core.netdev_max_backlog = 10000
net.core.rmem_default = 262144
net.core.rmem_max = 33554432
net.core.wmem_default = 262144
net.core.wmem_max = 33554432
net.ipv4.tcp_rmem = 4096 87380 33554432
net.ipv4.tcp_wmem = 4096 65536 33554432
net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_tw_reuse = 1
net.netfilter.nf_conntrack_max = 2097152
net.netfilter.nf_conntrack_tcp_timeout_established = 7200
vm.swappiness = 1
vm.dirty_ratio = 10
vm.dirty_background_ratio = 3
vm.overcommit_memory = 1
fs.file-max = 4194304
fs.nr_open = 4194304
EOF
else
    echo "Configuring QA kernel parameters..."
    sudo tee /etc/sysctl.d/99-rabbitmq.conf << 'EOF'
# QA RabbitMQ kernel parameters
net.core.somaxconn = 2048
net.core.rmem_max = 8388608
net.core.wmem_max = 8388608
vm.swappiness = 10
fs.file-max = 2097152
fs.nr_open = 2097152
EOF
fi

# Apply kernel parameters
echo "Applying kernel parameters..."
sudo sysctl -p /etc/sysctl.d/99-rabbitmq.conf

echo "Kernel parameters configuration completed!"
EOF

    chmod +x "$DEPLOYMENT_DIR/scripts/05-kernel-params.sh"
}

# Create firewall configuration script
create_firewall_script() {
    log "Creating firewall configuration script..."
    
    cat > "$DEPLOYMENT_DIR/scripts/06-firewall-config.sh" << 'EOF'
#!/bin/bash
# Firewall Configuration Script for Non-Root RabbitMQ

set -e

echo "=== Configuring Firewall (Non-Root) ==="

# Get environment and network details
read -p "Environment (qa/prod): " ENV
read -p "Application subnet (e.g., 10.20.30.0/24): " APP_SUBNET
read -p "Admin subnet (e.g., 10.20.40.0/24): " ADMIN_SUBNET

if [[ "$ENV" == "prod" ]]; then
    echo "Configuring production firewall rules..."
    
    # AMQP from application subnets only
    sudo firewall-cmd --permanent --add-rich-rule="rule family=\"ipv4\" source address=\"$APP_SUBNET\" port port=\"5672\" protocol=\"tcp\" accept"
    sudo firewall-cmd --permanent --add-rich-rule="rule family=\"ipv4\" source address=\"$APP_SUBNET\" port port=\"5671\" protocol=\"tcp\" accept"
    
    # Management from admin subnets only
    sudo firewall-cmd --permanent --add-rich-rule="rule family=\"ipv4\" source address=\"$ADMIN_SUBNET\" port port=\"15672\" protocol=\"tcp\" accept"
    sudo firewall-cmd --permanent --add-rich-rule="rule family=\"ipv4\" source address=\"$ADMIN_SUBNET\" port port=\"15671\" protocol=\"tcp\" accept"
    
    # Inter-node communication (requires specific node IPs)
    read -p "Node 1 IP: " NODE1_IP
    read -p "Node 2 IP: " NODE2_IP
    read -p "Node 3 IP: " NODE3_IP
    
    for node_ip in $NODE1_IP $NODE2_IP $NODE3_IP; do
        sudo firewall-cmd --permanent --add-rich-rule="rule family=\"ipv4\" source address=\"$node_ip\" port port=\"25672\" protocol=\"tcp\" accept"
        sudo firewall-cmd --permanent --add-rich-rule="rule family=\"ipv4\" source address=\"$node_ip\" port port=\"4369\" protocol=\"tcp\" accept"
        sudo firewall-cmd --permanent --add-rich-rule="rule family=\"ipv4\" source address=\"$node_ip\" port port=\"35672-35682\" protocol=\"tcp\" accept"
    done
    
else
    echo "Configuring QA firewall rules..."
    # Open ports for QA (less restrictive)
    sudo firewall-cmd --permanent --add-port=5672/tcp
    sudo firewall-cmd --permanent --add-port=15672/tcp
    sudo firewall-cmd --permanent --add-port=25672/tcp
    sudo firewall-cmd --permanent --add-port=4369/tcp
    sudo firewall-cmd --permanent --add-port=35672-35682/tcp
fi

# Prometheus monitoring
sudo firewall-cmd --permanent --add-port=15692/tcp

# Reload firewall
sudo firewall-cmd --reload

# Verify rules
echo "Current firewall rules:"
sudo firewall-cmd --list-all

echo "Firewall configuration completed!"
EOF

    chmod +x "$DEPLOYMENT_DIR/scripts/06-firewall-config.sh"
}

# Create configuration templates
create_config_templates() {
    log "Creating configuration templates..."
    
    # RabbitMQ configuration template
    cat > "$DEPLOYMENT_DIR/templates/rabbitmq.conf" << 'EOF'
# RabbitMQ 4.1.x Configuration Template
# Network configuration
listeners.tcp.default = 5672
management.tcp.port = 15672
management.tcp.ip = 0.0.0.0

# Prometheus configuration
prometheus.tcp.port = 15692
prometheus.tcp.ip = 0.0.0.0

# Memory configuration
vm_memory_high_watermark.relative = 0.6
vm_memory_high_watermark_paging_ratio = 0.5

# Disk configuration
disk_free_limit.relative = 2.0

# Logging configuration
log.console = true
log.console.level = info
log.file = true
log.file.level = info
log.file.rotation.date = $D0
log.file.rotation.size = 0

# Cluster configuration
cluster_formation.peer_discovery_backend = classic_config
cluster_formation.classic_config.nodes.1 = rabbit@NODE1_HOST
cluster_formation.classic_config.nodes.2 = rabbit@NODE2_HOST
cluster_formation.classic_config.nodes.3 = rabbit@NODE3_HOST

# Network partition handling
cluster_partition_handling = pause_minority

# Default queue type for data safety
default_queue_type = quorum

# Heartbeat
heartbeat = 60

# Statistics collection
collect_statistics_interval = 10000
EOF

    # Advanced configuration template
    cat > "$DEPLOYMENT_DIR/templates/advanced.config" << 'EOF'
[
  {rabbit, [
    {cluster_nodes, {['rabbit@NODE1_HOST', 'rabbit@NODE2_HOST', 'rabbit@NODE3_HOST'], disc}},
    {cluster_partition_handling, pause_minority},
    {tcp_listeners, [5672]},
    {num_tcp_acceptors, 10},
    {handshake_timeout, 10000},
    {vm_memory_high_watermark, 0.6},
    {heartbeat, 60},
    {channel_max, 2048},
    {connection_max, 2048},
    {collect_statistics_interval, 10000},
    {delegate_count, 16}
  ]},
  {rabbitmq_management, [
    {listener, [
      {port, 15672},
      {ip, "0.0.0.0"}
    ]}
  ]}
].
EOF

    # Enabled plugins template
    cat > "$DEPLOYMENT_DIR/templates/enabled_plugins" << 'EOF'
[rabbitmq_management,rabbitmq_management_agent,rabbitmq_prometheus,rabbitmq_federation,rabbitmq_shovel].
EOF

    # Definitions template
    cat > "$DEPLOYMENT_DIR/templates/definitions.json" << 'EOF'
{
  "rabbit_version": "4.1.0",
  "users": [
    {
      "name": "admin",
      "password_hash": "JHdweEWsIv6fs7B8JC4M3g7VhUJ5MiT5",
      "hashing_algorithm": "rabbit_password_hashing_sha256",
      "tags": ["administrator"]
    },
    {
      "name": "teja",
      "password_hash": "gqgGYdXzMFazKh6o7XZ0gO1nZiOQlFjj",
      "hashing_algorithm": "rabbit_password_hashing_sha256",
      "tags": ["management"]
    },
    {
      "name": "aswini",
      "password_hash": "kBvXz2oZEfU8RyXh9jNnK7cVdP6LmN3t",
      "hashing_algorithm": "rabbit_password_hashing_sha256",
      "tags": ["management"]
    }
  ],
  "vhosts": [
    {
      "name": "/"
    }
  ],
  "permissions": [
    {
      "user": "admin",
      "vhost": "/",
      "configure": ".*",
      "write": ".*",
      "read": ".*"
    },
    {
      "user": "teja",
      "vhost": "/",
      "configure": ".*",
      "write": ".*",
      "read": ".*"
    },
    {
      "user": "aswini",
      "vhost": "/",
      "configure": ".*",
      "write": ".*",
      "read": ".*"
    }
  ],
  "policies": [
    {
      "vhost": "/",
      "name": "quorum-queue-policy",
      "pattern": ".*",
      "apply-to": "queues",
      "definition": {
        "queue-type": "quorum",
        "overflow": "reject-publish"
      },
      "priority": 1
    }
  ]
}
EOF

    log "Configuration templates created in: $DEPLOYMENT_DIR/templates/"
}

# Create cluster setup script
create_cluster_script() {
    log "Creating cluster setup script..."
    
    cat > "$DEPLOYMENT_DIR/scripts/07-cluster-setup.sh" << 'EOF'
#!/bin/bash
# Cluster Setup Script for Non-Root RabbitMQ

set -e

echo "=== RabbitMQ Cluster Setup (Non-Root) ==="

# Get cluster information
read -p "Environment (qa/prod): " ENV
read -p "Node name (node1/node2/node3): " NODE_NAME
read -p "Node 1 hostname: " NODE1_HOST
read -p "Node 2 hostname: " NODE2_HOST
read -p "Node 3 hostname: " NODE3_HOST
read -p "Erlang cookie (or press Enter for default): " ERLANG_COOKIE
ERLANG_COOKIE=${ERLANG_COOKIE:-"SWQOKODSQALRPCLNMEQG"}

# Set hostname
echo "Setting hostname to $NODE_NAME..."
sudo hostnamectl set-hostname "$NODE_NAME"

# Update /etc/hosts
echo "Updating /etc/hosts..."
sudo sed -i '/# RabbitMQ Cluster Nodes/,+3d' /etc/hosts || true
sudo tee -a /etc/hosts << EOF
# RabbitMQ Cluster Nodes
${NODE1_HOST}    node1
${NODE2_HOST}    node2
${NODE3_HOST}    node3
EOF

# Stop RabbitMQ service if running
echo "Stopping RabbitMQ service..."
sudo systemctl stop rabbitmq-server 2>/dev/null || true

# Set Erlang cookie
echo "Setting Erlang cookie..."
echo "$ERLANG_COOKIE" | sudo tee /var/lib/rabbitmq/.erlang.cookie
sudo chown rabbitmq:rabbitmq /var/lib/rabbitmq/.erlang.cookie
sudo chmod 400 /var/lib/rabbitmq/.erlang.cookie

# Create configuration files
echo "Creating configuration files..."
sudo mkdir -p /etc/rabbitmq

# Create rabbitmq.conf
cat > /tmp/rabbitmq.conf << EOF
# RabbitMQ 4.1.x Configuration for $ENV environment
cluster_formation.peer_discovery_backend = classic_config
cluster_formation.classic_config.nodes.1 = rabbit@$NODE1_HOST
cluster_formation.classic_config.nodes.2 = rabbit@$NODE2_HOST
cluster_formation.classic_config.nodes.3 = rabbit@$NODE3_HOST

# Network partition handling
cluster_partition_handling = pause_minority

# Default queue type for data safety
default_queue_type = quorum

# Memory and disk limits
vm_memory_high_watermark.relative = 0.6
disk_free_limit.relative = 2.0

# Heartbeat
heartbeat = 60

# Management plugin
management.tcp.port = 15672
management.tcp.ip = 0.0.0.0

# Logging
log.console = true
log.console.level = info
log.file = /var/log/rabbitmq/rabbit.log
log.file.level = info

# Statistics collection
collect_statistics_interval = 10000
EOF

sudo cp /tmp/rabbitmq.conf /etc/rabbitmq/
sudo chown rabbitmq:rabbitmq /etc/rabbitmq/rabbitmq.conf
sudo chmod 644 /etc/rabbitmq/rabbitmq.conf

# Create enabled_plugins
echo "[rabbitmq_management,rabbitmq_management_agent,rabbitmq_prometheus,rabbitmq_federation,rabbitmq_shovel]." | sudo tee /etc/rabbitmq/enabled_plugins
sudo chown rabbitmq:rabbitmq /etc/rabbitmq/enabled_plugins
sudo chmod 644 /etc/rabbitmq/enabled_plugins

# Enable and start RabbitMQ service
echo "Enabling and starting RabbitMQ service..."
sudo systemctl enable rabbitmq-server
sudo systemctl start rabbitmq-server

# Wait for service to start
echo "Waiting for RabbitMQ to start..."
sleep 15

if [[ "$NODE_NAME" == "node1" ]]; then
    echo "Setting up primary node..."
    
    # Create admin user
    echo "Creating admin user..."
    sudo rabbitmqctl add_user admin admin123
    sudo rabbitmqctl set_user_tags admin administrator
    sudo rabbitmqctl set_permissions -p / admin ".*" ".*" ".*"
    
    # Create custom users
    echo "Creating custom users..."
    sudo rabbitmqctl add_user teja Teja@2024
    sudo rabbitmqctl set_user_tags teja management
    sudo rabbitmqctl set_permissions -p / teja ".*" ".*" ".*"
    
    sudo rabbitmqctl add_user aswini Aswini@2024
    sudo rabbitmqctl set_user_tags aswini management
    sudo rabbitmqctl set_permissions -p / aswini ".*" ".*" ".*"
    
    # Delete default guest user
    sudo rabbitmqctl delete_user guest
    
else
    echo "Setting up secondary node..."
    
    # Join cluster
    echo "Joining cluster..."
    sudo rabbitmqctl stop_app
    sudo rabbitmqctl reset
    sudo rabbitmqctl join_cluster rabbit@$NODE1_HOST
    sudo rabbitmqctl start_app
fi

# Check cluster status
echo "Checking cluster status..."
sudo rabbitmqctl cluster_status

echo "Node setup completed!"
EOF

    chmod +x "$DEPLOYMENT_DIR/scripts/07-cluster-setup.sh"
}

# Create management scripts
create_management_scripts() {
    log "Creating management scripts..."
    
    # Service management script
    cat > "$DEPLOYMENT_DIR/scripts/manage-service.sh" << 'EOF'
#!/bin/bash
# RabbitMQ Service Management Script for Non-Root User

case "$1" in
    start)
        echo "Starting RabbitMQ service..."
        sudo systemctl start rabbitmq-server
        ;;
    stop)
        echo "Stopping RabbitMQ service..."
        sudo systemctl stop rabbitmq-server
        ;;
    restart)
        echo "Restarting RabbitMQ service..."
        sudo systemctl restart rabbitmq-server
        ;;
    status)
        echo "RabbitMQ service status:"
        sudo systemctl status rabbitmq-server
        ;;
    enable)
        echo "Enabling RabbitMQ service..."
        sudo systemctl enable rabbitmq-server
        ;;
    disable)
        echo "Disabling RabbitMQ service..."
        sudo systemctl disable rabbitmq-server
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status|enable|disable}"
        exit 1
        ;;
esac
EOF

    # Cluster management script
    cat > "$DEPLOYMENT_DIR/scripts/manage-cluster.sh" << 'EOF'
#!/bin/bash
# RabbitMQ Cluster Management Script for Non-Root User

case "$1" in
    status)
        echo "Cluster status:"
        sudo rabbitmqctl cluster_status
        ;;
    join)
        if [[ -z "$2" ]]; then
            echo "Usage: $0 join <primary-node-hostname>"
            exit 1
        fi
        echo "Joining cluster with node: $2"
        sudo rabbitmqctl stop_app
        sudo rabbitmqctl reset
        sudo rabbitmqctl join_cluster rabbit@$2
        sudo rabbitmqctl start_app
        ;;
    leave)
        echo "Leaving cluster..."
        sudo rabbitmqctl stop_app
        sudo rabbitmqctl reset
        sudo rabbitmqctl start_app
        ;;
    nodes)
        echo "Cluster nodes:"
        sudo rabbitmqctl cluster_status | grep -A 10 "Cluster nodes"
        ;;
    *)
        echo "Usage: $0 {status|join <node>|leave|nodes}"
        exit 1
        ;;
esac
EOF

    # User management script
    cat > "$DEPLOYMENT_DIR/scripts/manage-users.sh" << 'EOF'
#!/bin/bash
# RabbitMQ User Management Script for Non-Root User

case "$1" in
    list)
        echo "RabbitMQ users:"
        sudo rabbitmqctl list_users
        ;;
    add)
        if [[ -z "$2" || -z "$3" ]]; then
            echo "Usage: $0 add <username> <password>"
            exit 1
        fi
        echo "Adding user: $2"
        sudo rabbitmqctl add_user "$2" "$3"
        sudo rabbitmqctl set_user_tags "$2" management
        sudo rabbitmqctl set_permissions -p / "$2" ".*" ".*" ".*"
        ;;
    delete)
        if [[ -z "$2" ]]; then
            echo "Usage: $0 delete <username>"
            exit 1
        fi
        echo "Deleting user: $2"
        sudo rabbitmqctl delete_user "$2"
        ;;
    change-password)
        if [[ -z "$2" || -z "$3" ]]; then
            echo "Usage: $0 change-password <username> <new-password>"
            exit 1
        fi
        echo "Changing password for user: $2"
        sudo rabbitmqctl change_password "$2" "$3"
        ;;
    *)
        echo "Usage: $0 {list|add <user> <pass>|delete <user>|change-password <user> <pass>}"
        exit 1
        ;;
esac
EOF

    # Monitoring script
    cat > "$DEPLOYMENT_DIR/scripts/monitor-cluster.sh" << 'EOF'
#!/bin/bash
# RabbitMQ Cluster Monitoring Script for Non-Root User

echo "=== RabbitMQ Cluster Health Check ==="

# Check service status
echo "1. Service Status:"
sudo systemctl is-active rabbitmq-server

# Check cluster status
echo "2. Cluster Status:"
sudo rabbitmqctl cluster_status

# Check node health
echo "3. Node Health:"
sudo rabbitmqctl node_health_check

# Check connections
echo "4. Active Connections:"
sudo rabbitmqctl list_connections | wc -l

# Check queues
echo "5. Queue Overview:"
sudo rabbitmqctl list_queues name type messages consumers

# Check memory usage
echo "6. Memory Usage:"
sudo rabbitmqctl status | grep -A 3 "Memory"

# Check for alarms
echo "7. Cluster Alarms:"
sudo rabbitmqctl eval 'rabbit_alarm:get_alarms().'

echo "Health check completed!"
EOF

    # Make all management scripts executable
    chmod +x "$DEPLOYMENT_DIR/scripts/manage-"*.sh
    chmod +x "$DEPLOYMENT_DIR/scripts/monitor-cluster.sh"
}

# Create validation script
create_validation_script() {
    log "Creating validation script..."
    
    cat > "$DEPLOYMENT_DIR/scripts/validate-setup.sh" << 'EOF'
#!/bin/bash
# RabbitMQ Setup Validation Script for Non-Root User

echo "=== RabbitMQ Setup Validation ==="

# Check system limits
echo "1. System Limits:"
echo "   Current nofile limit: $(ulimit -n)"
echo "   Required: 65536+ for QA, 300000+ for Production"

# Check kernel parameters
echo "2. Kernel Parameters:"
echo "   somaxconn: $(cat /proc/sys/net/core/somaxconn)"
echo "   swappiness: $(cat /proc/sys/vm/swappiness)"

# Check RabbitMQ service status
echo "3. RabbitMQ Service:"
echo "   Status: $(sudo systemctl is-active rabbitmq-server)"
echo "   Enabled: $(sudo systemctl is-enabled rabbitmq-server)"

# Check RabbitMQ cluster status
echo "4. Cluster Status:"
sudo rabbitmqctl cluster_status

# Check RabbitMQ node health
echo "5. Node Health:"
sudo rabbitmqctl node_health_check

# Check queue types
echo "6. Default Queue Type:"
sudo rabbitmqctl environment | grep default_queue_type

# Check firewall
echo "7. Firewall Status:"
sudo firewall-cmd --list-ports

# Check disk space
echo "8. Disk Space:"
df -h /var/lib/rabbitmq
df -h /var/log/rabbitmq

# Check memory usage
echo "9. Memory Usage:"
free -h

echo "Validation completed!"
EOF

    chmod +x "$DEPLOYMENT_DIR/scripts/validate-setup.sh"
}

# Create master deployment script
create_master_script() {
    log "Creating master deployment script..."
    
    cat > "$DEPLOYMENT_DIR/deploy-rabbitmq.sh" << 'EOF'
#!/bin/bash
# Master RabbitMQ Deployment Script for Non-Root User

set -e

echo "=== RabbitMQ 4.1.x Non-Root Deployment Workflow ==="

# Make all scripts executable
chmod +x ~/rabbitmq-deployment/scripts/*.sh

# Step 1: System preparation
echo "Step 1: System Preparation"
~/rabbitmq-deployment/scripts/01-system-preparation.sh

# Step 2: Repository setup
echo "Step 2: Repository Setup"
~/rabbitmq-deployment/scripts/02-repo-setup.sh

# Step 3: RabbitMQ installation
echo "Step 3: RabbitMQ Installation"
~/rabbitmq-deployment/scripts/03-rabbitmq-install.sh

# Step 4: System limits configuration
echo "Step 4: System Limits Configuration"
~/rabbitmq-deployment/scripts/04-system-limits.sh

# Step 5: Kernel parameters
echo "Step 5: Kernel Parameters Configuration"
~/rabbitmq-deployment/scripts/05-kernel-params.sh

# Step 6: Firewall configuration
echo "Step 6: Firewall Configuration"
~/rabbitmq-deployment/scripts/06-firewall-config.sh

# Step 7: Cluster setup
echo "Step 7: Cluster Setup"
~/rabbitmq-deployment/scripts/07-cluster-setup.sh

# Step 8: Validate setup
echo "Step 8: Setup Validation"
~/rabbitmq-deployment/scripts/validate-setup.sh

echo "=== RabbitMQ Deployment Completed Successfully! ==="
echo "Management Interface: http://$(hostname):15672"
echo "Available Credentials:"
echo "  - admin/admin123 (Administrator)"
echo "  - teja/Teja@2024 (Management User)"
echo "  - aswini/Aswini@2024 (Management User)"
echo ""
echo "Management Scripts Available:"
echo "  - ~/rabbitmq-deployment/scripts/manage-service.sh"
echo "  - ~/rabbitmq-deployment/scripts/manage-cluster.sh"
echo "  - ~/rabbitmq-deployment/scripts/manage-users.sh"
echo "  - ~/rabbitmq-deployment/scripts/monitor-cluster.sh"
EOF

    chmod +x "$DEPLOYMENT_DIR/deploy-rabbitmq.sh"
}

# Create documentation
create_documentation() {
    log "Creating documentation..."
    
    cat > "$DEPLOYMENT_DIR/README.md" << 'EOF'
# RabbitMQ 4.1.x Non-Root Deployment Guide

## Overview
This deployment provides RabbitMQ 4.1.x cluster installation and management capabilities for non-root users with minimal sudo privileges.

## Prerequisites
1. Non-root user account with sudo access to specific commands
2. System administrator must configure sudoers file
3. RHEL 8.x system

## Quick Start

### 1. Setup Sudoers Configuration
Ask your system administrator to copy the sudoers configuration:
```bash
sudo cp ~/rabbitmq-deployment/sudoers-rabbitmq.conf /etc/sudoers.d/rabbitmq-deployment
```

### 2. Run Master Deployment
```bash
cd ~/rabbitmq-deployment
./deploy-rabbitmq.sh
```

### 3. Individual Scripts
If you prefer to run scripts individually:
```bash
# System preparation
./scripts/01-system-preparation.sh

# Repository setup
./scripts/02-repo-setup.sh

# RabbitMQ installation
./scripts/03-rabbitmq-install.sh

# System limits
./scripts/04-system-limits.sh

# Kernel parameters
./scripts/05-kernel-params.sh

# Firewall configuration
./scripts/06-firewall-config.sh

# Cluster setup
./scripts/07-cluster-setup.sh

# Validation
./scripts/validate-setup.sh
```

## Management Scripts

### Service Management
```bash
# Start/stop/restart RabbitMQ
./scripts/manage-service.sh start
./scripts/manage-service.sh stop
./scripts/manage-service.sh restart
./scripts/manage-service.sh status
```

### Cluster Management
```bash
# Check cluster status
./scripts/manage-cluster.sh status

# Join cluster
./scripts/manage-cluster.sh join node1

# Leave cluster
./scripts/manage-cluster.sh leave

# List cluster nodes
./scripts/manage-cluster.sh nodes
```

### User Management
```bash
# List users
./scripts/manage-users.sh list

# Add user
./scripts/manage-users.sh add username password

# Delete user
./scripts/manage-users.sh delete username

# Change password
./scripts/manage-users.sh change-password username newpassword
```

### Monitoring
```bash
# Health check
./scripts/monitor-cluster.sh
```

## Configuration Files
- `templates/rabbitmq.conf` - Main RabbitMQ configuration
- `templates/advanced.config` - Advanced Erlang configuration
- `templates/enabled_plugins` - Enabled plugins list
- `templates/definitions.json` - User and permission definitions

## Security Notes
1. Default users are created with strong passwords
2. Firewall rules are configured based on environment
3. SSL/TLS configuration can be added as needed
4. Regular security updates should be applied

## Troubleshooting
1. Check service status: `sudo systemctl status rabbitmq-server`
2. Check logs: `sudo journalctl -u rabbitmq-server -f`
3. Validate setup: `./scripts/validate-setup.sh`
4. Monitor cluster: `./scripts/monitor-cluster.sh`

## Support
For issues or questions, refer to the main documentation or contact your system administrator.
EOF

    log "Documentation created: $DEPLOYMENT_DIR/README.md"
}

# Main execution
main() {
    log "Starting RabbitMQ Non-Root Setup..."
    
    check_user
    create_directories
    create_sudoers_config
    create_system_prep_script
    create_repo_script
    create_install_script
    create_limits_script
    create_kernel_script
    create_firewall_script
    create_config_templates
    create_cluster_script
    create_management_scripts
    create_validation_script
    create_master_script
    create_documentation
    
    log "RabbitMQ Non-Root Setup completed successfully!"
    log "Deployment directory: $DEPLOYMENT_DIR"
    log "Next steps:"
    log "1. Ask system administrator to configure sudoers file"
    log "2. Run: cd $DEPLOYMENT_DIR && ./deploy-rabbitmq.sh"
    log "3. Use management scripts for ongoing operations"
}

# Run main function
main "$@"
