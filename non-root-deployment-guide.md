# RabbitMQ 4.1.x Non-Root User Deployment Guide

## Document Information
- **Version**: 1.0
- **Target**: RHEL 8.x deployment with non-root user
- **RabbitMQ Version**: 4.1.x
- **Deployment Method**: Manual installation without root privileges

## 1. Prerequisites and Assumptions

### 1.1 User Account Requirements
```bash
# User account: rabbitmq-admin (or your designated non-root user)
# Home directory: /home/rabbitmq-admin
# Groups: wheel (for sudo access to specific commands)

# Required sudo privileges (to be configured by system administrator):
# - Package installation commands
# - Service management commands
# - Firewall configuration commands
# - File system operations for RabbitMQ directories
```

### 1.2 Directory Structure Setup
```bash
# Create directory structure in user home
mkdir -p ~/rabbitmq-deployment/{config,scripts,logs,data,ssl,backup}
mkdir -p ~/rabbitmq-deployment/systemd-override

# Set working directory
cd ~/rabbitmq-deployment
```

### 1.3 Required sudo Access Configuration
```bash
# Request system administrator to add this to /etc/sudoers.d/rabbitmq-deployment:

# User alias for RabbitMQ admin
User_Alias RABBITMQ_ADMINS = rabbitmq-admin

# Command aliases for RabbitMQ operations
Cmnd_Alias RABBITMQ_INSTALL = /usr/bin/dnf install *, /usr/bin/rpm --import *, /usr/bin/tee /etc/yum.repos.d/*
Cmnd_Alias RABBITMQ_SERVICE = /usr/bin/systemctl * rabbitmq-server, /usr/sbin/rabbitmqctl *, /usr/sbin/rabbitmq-plugins *
Cmnd_Alias RABBITMQ_CONFIG = /usr/bin/tee /etc/rabbitmq/*, /usr/bin/mkdir -p /etc/rabbitmq/*, /usr/bin/chown *, /usr/bin/chmod *
Cmnd_Alias RABBITMQ_FIREWALL = /usr/bin/firewall-cmd *
Cmnd_Alias RABBITMQ_SYSCTL = /usr/sbin/sysctl *, /usr/bin/tee /etc/sysctl.d/*, /usr/bin/tee /etc/systemd/system/*
Cmnd_Alias RABBITMQ_LIMITS = /usr/bin/tee /etc/security/limits.d/*, /usr/bin/tee -a /etc/security/limits.conf

# Grant permissions
RABBITMQ_ADMINS ALL=(ALL) NOPASSWD: RABBITMQ_INSTALL, RABBITMQ_SERVICE, RABBITMQ_CONFIG, RABBITMQ_FIREWALL, RABBITMQ_SYSCTL, RABBITMQ_LIMITS
```

## 2. Non-Root Installation Process

### 2.1 System Preparation Script
```bash
#!/bin/bash
# File: ~/rabbitmq-deployment/scripts/01-system-preparation.sh

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
```

### 2.2 Repository Configuration Script
```bash
#!/bin/bash
# File: ~/rabbitmq-deployment/scripts/02-repo-setup.sh

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
```

### 2.3 RabbitMQ Installation Script
```bash
#!/bin/bash
# File: ~/rabbitmq-deployment/scripts/03-rabbitmq-install.sh

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

echo "RabbitMQ installation completed!"
```

### 2.4 System Limits Configuration Script
```bash
#!/bin/bash
# File: ~/rabbitmq-deployment/scripts/04-system-limits.sh

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
```

### 2.5 Kernel Parameters Configuration Script
```bash
#!/bin/bash
# File: ~/rabbitmq-deployment/scripts/05-kernel-params.sh

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
```

### 2.6 Firewall Configuration Script
```bash
#!/bin/bash
# File: ~/rabbitmq-deployment/scripts/06-firewall-config.sh

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
```

## 3. Configuration Files Deployment

### 3.1 Configuration Files Creation Script
```bash
#!/bin/bash
# File: ~/rabbitmq-deployment/scripts/07-create-configs.sh

set -e

echo "=== Creating RabbitMQ Configuration Files (Non-Root) ==="

# Get cluster information
read -p "Environment (qa/prod): " ENV
read -p "Node name (node1/node2/node3): " NODE_NAME
read -p "Node 1 hostname: " NODE1_HOST
read -p "Node 2 hostname: " NODE2_HOST
read -p "Node 3 hostname: " NODE3_HOST

# Create configuration directory structure
sudo mkdir -p /etc/rabbitmq/ssl
sudo chown rabbitmq:rabbitmq /etc/rabbitmq
sudo chown rabbitmq:rabbitmq /etc/rabbitmq/ssl

# Create main configuration file
echo "Creating rabbitmq.conf..."
cat > ~/rabbitmq-deployment/config/rabbitmq.conf << EOF
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

# Create advanced configuration
echo "Creating advanced.config..."
cat > ~/rabbitmq-deployment/config/advanced.config << 'EOF'
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

# Replace placeholders
sed -i "s/NODE1_HOST/$NODE1_HOST/g" ~/rabbitmq-deployment/config/advanced.config
sed -i "s/NODE2_HOST/$NODE2_HOST/g" ~/rabbitmq-deployment/config/advanced.config
sed -i "s/NODE3_HOST/$NODE3_HOST/g" ~/rabbitmq-deployment/config/advanced.config

# Create enabled plugins file
echo "Creating enabled_plugins..."
cat > ~/rabbitmq-deployment/config/enabled_plugins << 'EOF'
[rabbitmq_management,rabbitmq_management_agent,rabbitmq_prometheus,rabbitmq_federation,rabbitmq_shovel].
EOF

# Create definitions file
echo "Creating definitions.json..."
cat > ~/rabbitmq-deployment/config/definitions.json << 'EOF'
{
  "rabbit_version": "4.1.0",
  "users": [
    {
      "name": "admin",
      "password_hash": "JHdweEWsIv6fs7B8JC4M3g7VhUJ5MiT5",
      "hashing_algorithm": "rabbit_password_hashing_sha256",
      "tags": ["administrator"]
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

echo "Configuration files created in ~/rabbitmq-deployment/config/"
```

### 3.2 Configuration Deployment Script
```bash
#!/bin/bash
# File: ~/rabbitmq-deployment/scripts/08-deploy-configs.sh

set -e

echo "=== Deploying RabbitMQ Configuration Files (Non-Root) ==="

# Copy configuration files to RabbitMQ directory
echo "Copying configuration files..."
sudo cp ~/rabbitmq-deployment/config/rabbitmq.conf /etc/rabbitmq/
sudo cp ~/rabbitmq-deployment/config/advanced.config /etc/rabbitmq/
sudo cp ~/rabbitmq-deployment/config/enabled_plugins /etc/rabbitmq/
sudo cp ~/rabbitmq-deployment/config/definitions.json /etc/rabbitmq/

# Set proper ownership and permissions
echo "Setting ownership and permissions..."
sudo chown rabbitmq:rabbitmq /etc/rabbitmq/*
sudo chmod 644 /etc/rabbitmq/rabbitmq.conf
sudo chmod 644 /etc/rabbitmq/advanced.config
sudo chmod 644 /etc/rabbitmq/enabled_plugins
sudo chmod 644 /etc/rabbitmq/definitions.json

# Create data and log directories
sudo mkdir -p /var/lib/rabbitmq /var/log/rabbitmq
sudo chown -R rabbitmq:rabbitmq /var/lib/rabbitmq /var/log/rabbitmq
sudo chmod 755 /var/lib/rabbitmq /var/log/rabbitmq

echo "Configuration deployment completed!"
```

## 4. Cluster Setup Process

### 4.1 Erlang Cookie Configuration Script
```bash
#!/bin/bash
# File: ~/rabbitmq-deployment/scripts/09-setup-cookie.sh

set -e

echo "=== Setting up Erlang Cookie (Non-Root) ==="

# Get the Erlang cookie (should be same across all nodes)
read -p "Enter Erlang cookie (or press Enter for default): " ERLANG_COOKIE
ERLANG_COOKIE=${ERLANG_COOKIE:-"SWQOKODSQALRPCLNMEQG"}

# Stop RabbitMQ service if running
echo "Stopping RabbitMQ service..."
sudo systemctl stop rabbitmq-server 2>/dev/null || true

# Set Erlang cookie
echo "Setting Erlang cookie..."
echo "$ERLANG_COOKIE" | sudo tee /var/lib/rabbitmq/.erlang.cookie
sudo chown rabbitmq:rabbitmq /var/lib/rabbitmq/.erlang.cookie
sudo chmod 400 /var/lib/rabbitmq/.erlang.cookie

echo "Erlang cookie configuration completed!"
echo "Cookie set to: $ERLANG_COOKIE"
echo "Make sure this cookie is IDENTICAL on all cluster nodes!"
```

### 4.2 Service Start and Cluster Join Script
```bash
#!/bin/bash
# File: ~/rabbitmq-deployment/scripts/10-start-and-join.sh

set -e

echo "=== Starting RabbitMQ and Joining Cluster (Non-Root) ==="

# Get node information
read -p "Is this the primary node (node1)? (y/n): " IS_PRIMARY
read -p "Node name: " NODE_NAME

# Enable and start RabbitMQ service
echo "Enabling and starting RabbitMQ service..."
sudo systemctl enable rabbitmq-server
sudo systemctl start rabbitmq-server

# Wait for service to start
echo "Waiting for RabbitMQ to start..."
sleep 15

if [[ "$IS_PRIMARY" == "y" ]]; then
    echo "Setting up primary node..."
    
    # Create admin user
    echo "Creating admin user..."
    sudo rabbitmqctl add_user admin admin123
    sudo rabbitmqctl set_user_tags admin administrator
    sudo rabbitmqctl set_permissions -p / admin ".*" ".*" ".*"
    
    # Delete default guest user
    sudo rabbitmqctl delete_user guest
    
else
    echo "Setting up secondary node..."
    read -p "Primary node hostname: " PRIMARY_NODE
    
    # Join cluster
    echo "Joining cluster..."
    sudo rabbitmqctl stop_app
    sudo rabbitmqctl reset
    sudo rabbitmqctl join_cluster rabbit@$PRIMARY_NODE
    sudo rabbitmqctl start_app
fi

# Check cluster status
echo "Checking cluster status..."
sudo rabbitmqctl cluster_status

echo "Node setup completed!"
```

## 5. Validation and Monitoring Scripts

### 5.1 System Validation Script
```bash
#!/bin/bash
# File: ~/rabbitmq-deployment/scripts/11-validate-system.sh

echo "=== RabbitMQ System Validation (Non-Root) ==="

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

echo "System validation completed!"
```

### 5.2 Cluster Health Monitoring Script
```bash
#!/bin/bash
# File: ~/rabbitmq-deployment/scripts/12-monitor-cluster.sh

echo "=== RabbitMQ Cluster Health Monitoring (Non-Root) ==="

# Function to check node connectivity
check_node_connectivity() {
    local node=$1
    if ping -c 1 $node >/dev/null 2>&1; then
        echo "✓ $node: Network connectivity OK"
    else
        echo "✗ $node: Network connectivity FAILED"
    fi
}

# Function to check RabbitMQ service on node
check_rabbitmq_service() {
    local node=$1
    if ssh -o ConnectTimeout=5 $node "sudo systemctl is-active rabbitmq-server" >/dev/null 2>&1; then
        echo "✓ $node: RabbitMQ service OK"
    else
        echo "✗ $node: RabbitMQ service FAILED"
    fi
}

# Get cluster node information
read -p "Node 1 hostname: " NODE1
read -p "Node 2 hostname: " NODE2
read -p "Node 3 hostname: " NODE3

echo "Checking cluster health..."

# Check network connectivity
echo "1. Network Connectivity:"
for node in $NODE1 $NODE2 $NODE3; do
    check_node_connectivity $node
done

# Check RabbitMQ services
echo "2. RabbitMQ Services:"
for node in $NODE1 $NODE2 $NODE3; do
    check_rabbitmq_service $node
done

# Check cluster status
echo "3. Cluster Status:"
sudo rabbitmqctl cluster_status

# Check queue overview
echo "4. Queue Overview:"
sudo rabbitmqctl list_queues name type messages consumers

# Check connection count
echo "5. Active Connections:"
sudo rabbitmqctl list_connections | wc -l

# Check memory usage per node
echo "6. Memory Usage:"
sudo rabbitmqctl status | grep -A 3 "Memory"

# Check for alarms
echo "7. Cluster Alarms:"
sudo rabbitmqctl eval 'rabbit_alarm:get_alarms().'

echo "Cluster health check completed!"
```

## 6. Backup and Maintenance Scripts

### 6.1 Backup Script
```bash
#!/bin/bash
# File: ~/rabbitmq-deployment/scripts/13-backup.sh

set -e

echo "=== RabbitMQ Backup (Non-Root) ==="

# Create backup directory
BACKUP_DIR="~/rabbitmq-deployment/backup/$(date +%Y%m%d_%H%M%S)"
mkdir -p $BACKUP_DIR

echo "Creating backup in: $BACKUP_DIR"

# Export definitions
echo "Exporting definitions..."
sudo rabbitmqctl export_definitions $BACKUP_DIR/definitions.json

# Backup configuration files
echo "Backing up configuration files..."
sudo cp /etc/rabbitmq/rabbitmq.conf $BACKUP_DIR/
sudo cp /etc/rabbitmq/advanced.config $BACKUP_DIR/
sudo cp /etc/rabbitmq/enabled_plugins $BACKUP_DIR/

# Create system information snapshot
echo "Creating system information snapshot..."
cat > $BACKUP_DIR/system_info.txt << EOF
Backup Date: $(date)
Hostname: $(hostname)
RabbitMQ Version: $(sudo rabbitmqctl version)
Cluster Status: $(sudo rabbitmqctl cluster_status)
Queue List: $(sudo rabbitmqctl list_queues name type messages)
EOF

echo "Backup completed: $BACKUP_DIR"
```

### 6.2 Log Rotation Script
```bash
#!/bin/bash
# File: ~/rabbitmq-deployment/scripts/14-log-rotation.sh

echo "=== Setting up RabbitMQ Log Rotation (Non-Root) ==="

# Create log rotation configuration
sudo tee /etc/logrotate.d/rabbitmq << 'EOF'
/var/log/rabbitmq/*.log {
    daily
    missingok
    rotate 30
    compress
    delaycompress
    notifempty
    create 0644 rabbitmq rabbitmq
    postrotate
        systemctl reload rabbitmq-server > /dev/null 2>&1 || true
    endscript
}
EOF

echo "Log rotation configured"
echo "Logs will be rotated daily and kept for 30 days"
```

## 7. Complete Deployment Workflow

### 7.1 Master Deployment Script
```bash
#!/bin/bash
# File: ~/rabbitmq-deployment/deploy-rabbitmq.sh

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

# Step 7: Create configuration files
echo "Step 7: Create Configuration Files"
~/rabbitmq-deployment/scripts/07-create-configs.sh

# Step 8: Deploy configurations
echo "Step 8: Deploy Configurations"
~/rabbitmq-deployment/scripts/08-deploy-configs.sh

# Step 9: Setup Erlang cookie
echo "Step 9: Setup Erlang Cookie"
~/rabbitmq-deployment/scripts/09-setup-cookie.sh

# Step 10: Start and join cluster
echo "Step 10: Start and Join Cluster"
~/rabbitmq-deployment/scripts/10-start-and-join.sh

# Step 11: Validate system
echo "Step 11: System Validation"
~/rabbitmq-deployment/scripts/11-validate-system.sh

# Step 12: Setup monitoring
echo "Step 12: Setup Monitoring"
~/rabbitmq-deployment/scripts/12-monitor-cluster.sh

# Step 13: Setup backup
echo "Step 13: Setup Backup"
~/rabbitmq-deployment/scripts/13-backup.sh

# Step 14: Setup log rotation
echo "Step 14: Setup Log Rotation"
~/rabbitmq-deployment/scripts/14-log-rotation.sh

echo "=== RabbitMQ Deployment Completed Successfully! ==="
echo "Management Interface: http://$(hostname):15672"
echo "Default Credentials: admin/admin123"
echo "Next Steps:"
echo "1. Configure SSL certificates if needed"
echo "2. Set up monitoring and alerting"
echo "3. Create application-specific users and vhosts"
echo "4. Test application connectivity"
```

## 8. Troubleshooting Guide

### 8.1 Common Issues and Solutions

#### Permission Issues
```bash
# If you encounter permission errors:
# 1. Check sudo configuration
sudo -l

# 2. Verify file ownership
ls -la /etc/rabbitmq/
ls -la /var/lib/rabbitmq/
ls -la /var/log/rabbitmq/

# 3. Fix ownership if needed
sudo chown -R rabbitmq:rabbitmq /var/lib/rabbitmq/
sudo chown -R rabbitmq:rabbitmq /var/log/rabbitmq/
```

#### Service Start Issues
```bash
# Check service status
sudo systemctl status rabbitmq-server

# Check logs
sudo journalctl -u rabbitmq-server -f

# Check RabbitMQ logs
sudo tail -f /var/log/rabbitmq/rabbit@$(hostname).log
```

#### Cluster Join Issues
```bash
# Reset and rejoin cluster
sudo rabbitmqctl stop_app
sudo rabbitmqctl reset
sudo rabbitmqctl join_cluster rabbit@primary-node
sudo rabbitmqctl start_app
```

### 8.2 Emergency Procedures
```bash
# Stop all RabbitMQ processes
sudo systemctl stop rabbitmq-server
sudo pkill -f rabbitmq

# Start in safe mode
sudo rabbitmq-server -detached

# Force cluster reset (CAUTION: Data loss possible)
sudo rabbitmqctl force_reset
```

This comprehensive non-root deployment guide ensures that RabbitMQ 4.1.x can be deployed safely without direct root access while maintaining security and operational excellence.