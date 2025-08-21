# RabbitMQ 4.1.x Complete Manual Deployment Guide

## Overview

This comprehensive manual deployment guide covers the complete RabbitMQ 4.1.x deployment workflow including:
- Environment-based configuration setup
- Cluster deployment with auto-recovery
- Operational procedures and monitoring
- Cluster recovery and troubleshooting
- Production best practices

## 🎯 Quick Start Summary

For experienced users who want to get started immediately:

```bash
# 1. Download deployment files
git clone https://github.com/Tejaswinireddys/RabbitMQ.git
cd RabbitMQ

# 2. Choose environment and view configuration
./load-environment.sh list
./load-environment.sh show prod

# 3. Setup cluster
./cluster-setup-environment.sh -e prod -r primary    # On primary node
./cluster-setup-environment.sh -e prod -r secondary  # On secondary nodes

# 4. Start monitoring
./cluster-auto-recovery-monitor.sh -e prod -d

# 5. Access dashboard
./environment-operations.sh operations-menu prod
```

## 1. Prerequisites and System Setup

### 1.1 System Requirements

#### Minimum Requirements
- **Operating System**: RHEL 8.x / CentOS 8 / Rocky Linux 8
- **Memory**: 4GB RAM per node (8GB+ recommended for production)
- **CPU**: 2 cores per node (4+ cores recommended for production)
- **Disk**: 20GB free space per node (100GB+ for production)
- **Network**: Static IP addresses with reliable connectivity
- **User Access**: Root or sudo privileges

#### Production Requirements
- **Memory**: 16GB+ RAM per node
- **CPU**: 8+ cores per node
- **Disk**: 500GB+ with SSD storage
- **Network**: Dedicated network with redundancy
- **Monitoring**: Prometheus, Grafana, alerting systems

### 1.2 Network Planning

#### IP Address Planning
Plan your IP addresses for each environment:

```bash
# Production Environment
Node 1: 10.20.20.10    (prod-rmq-node1)
Node 2: 10.20.20.11    (prod-rmq-node2)
Node 3: 10.20.20.12    (prod-rmq-node3)
VIP:    10.20.20.100   (Load balancer)

# Staging Environment  
Node 1: 10.15.15.10    (staging-rmq-node1)
Node 2: 10.15.15.11    (staging-rmq-node2)
Node 3: 10.15.15.12    (staging-rmq-node3)
VIP:    10.15.15.100

# QA Environment
Node 1: 10.10.10.10    (qa-rmq-node1)
Node 2: 10.10.10.11    (qa-rmq-node2)
Node 3: 10.10.10.12    (qa-rmq-node3)
VIP:    10.10.10.100
```

### 1.3 Firewall Configuration (Run on ALL nodes)

```bash
# RabbitMQ Core Ports
sudo firewall-cmd --permanent --add-port=5672/tcp   # AMQP
sudo firewall-cmd --permanent --add-port=15672/tcp  # Management UI
sudo firewall-cmd --permanent --add-port=25672/tcp  # Inter-node communication
sudo firewall-cmd --permanent --add-port=4369/tcp   # EPMD port mapper

# Erlang Distribution Range
sudo firewall-cmd --permanent --add-port=35672-35682/tcp

# SSL/TLS Ports (if SSL enabled)
sudo firewall-cmd --permanent --add-port=5671/tcp   # AMQP SSL
sudo firewall-cmd --permanent --add-port=15671/tcp  # Management SSL

# Monitoring Ports
sudo firewall-cmd --permanent --add-port=15692/tcp  # Prometheus metrics

# Apply changes
sudo firewall-cmd --reload

# Verify configuration
sudo firewall-cmd --list-ports
```

### 1.4 SELinux Configuration (Run on ALL nodes)

```bash
# Option 1: Set to permissive (easier)
sudo setenforce 0
sudo sed -i 's/SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config

# Option 2: Configure SELinux properly (production recommended)
sudo setsebool -P nis_enabled 1
sudo semanage port -a -t cluster_port_t -p tcp 25672
sudo semanage port -a -t cluster_port_t -p tcp 35672-35682
```

## 2. Software Installation

### 2.1 Install Dependencies (Run on ALL nodes)

```bash
# Update system
sudo dnf update -y

# Install EPEL repository
sudo dnf install -y epel-release

# Install required packages
sudo dnf install -y curl wget gnupg2 socat logrotate jq mail

# Install development tools (for SSL certificate generation)
sudo dnf groupinstall -y "Development Tools"

# Install monitoring tools
sudo dnf install -y htop iotop nethogs
```

### 2.2 Install Erlang (Run on ALL nodes)

```bash
# Install Erlang 26.x (required for RabbitMQ 4.1.x)
sudo dnf install -y erlang

# Verify Erlang installation
erl -version
# Expected output: Erlang (SMP,ASYNC_THREADS) (BEAM) emulator version 14.x

# Test Erlang
erl -eval 'io:format("Erlang working~n"), halt().' -noshell
```

### 2.3 Install RabbitMQ (Run on ALL nodes)

```bash
# Add RabbitMQ repository
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
sudo rpm --import https://github.com/rabbitmq/signing-keys/releases/download/3.0/cloudsmith.rabbitmq-server.9F4587F226208342.key

# Install RabbitMQ 4.1.x
sudo dnf install -y rabbitmq-server

# Verify installation
rabbitmq-diagnostics --version
# Expected output: RabbitMQ version: 4.1.x

# Create necessary directories
sudo mkdir -p /etc/rabbitmq /var/log/rabbitmq /var/lib/rabbitmq /backup/rabbitmq
sudo chown -R rabbitmq:rabbitmq /var/log/rabbitmq /var/lib/rabbitmq /etc/rabbitmq
sudo chmod 755 /backup/rabbitmq
```

## 3. Environment Configuration Setup

### 3.1 Download Deployment Scripts

```bash
# Clone the deployment repository
cd /opt
sudo git clone https://github.com/Tejaswinireddys/RabbitMQ.git rabbitmq-deployment
sudo chown -R $(whoami):$(whoami) /opt/rabbitmq-deployment
cd /opt/rabbitmq-deployment

# Make scripts executable
chmod +x *.sh

# Verify deployment files
ls -la
# Should see: load-environment.sh, cluster-setup-environment.sh, etc.
```

### 3.2 Configure Your Environment

```bash
# List available environments
./load-environment.sh list

# For new environments, create from template
./environment-manager.sh create your-env-name

# Or use existing environments (qa, staging, prod)
# Edit the environment file for your specific setup
cp environments/prod.env environments/prod.env.backup
vi environments/prod.env
```

#### Example Production Environment Configuration

```bash
# Update environments/prod.env with your specific details:

# === Environment Info ===
ENVIRONMENT_NAME="prod"
ENVIRONMENT_TYPE="production"

# === Cluster Name (Environment Specific) ===
RABBITMQ_CLUSTER_NAME="rabbitmq-prod-cluster"

# === Node Configuration (UPDATE WITH YOUR HOSTNAMES) ===
RABBITMQ_NODE_1_HOSTNAME="prod-rmq-node1"
RABBITMQ_NODE_2_HOSTNAME="prod-rmq-node2" 
RABBITMQ_NODE_3_HOSTNAME="prod-rmq-node3"

# === IP Addresses (UPDATE WITH YOUR IPs) ===
RABBITMQ_NODE_1_IP="10.20.20.10"
RABBITMQ_NODE_2_IP="10.20.20.11"
RABBITMQ_NODE_3_IP="10.20.20.12"

# === Load Balancer Configuration ===
RABBITMQ_VIP="10.20.20.100"
HAPROXY_HOST="10.20.20.101"

# === Custom Users (UPDATE PASSWORDS) ===
RABBITMQ_CUSTOM_USER_1="teja"
RABBITMQ_CUSTOM_USER_1_PASS="YourSecurePassword123!"
RABBITMQ_CUSTOM_USER_2="aswini"
RABBITMQ_CUSTOM_USER_2_PASS="YourSecurePassword456!"

# === Auto-Recovery Settings ===
RABBITMQ_FORCE_BOOT_ON_STARTUP="false"  # Conservative for production
RABBITMQ_AUTO_RECOVERY_DELAY="60"
```

### 3.3 Validate Environment Configuration

```bash
# Validate configuration
./load-environment.sh validate prod

# Show environment details
./load-environment.sh show prod

# Check syntax
./environment-manager.sh check-syntax prod
```

### 3.4 Generate Configuration Files

```bash
# Generate environment-specific RabbitMQ configurations
./generate-configs.sh prod

# Review generated files
ls -la *.conf *.config *.json
cat rabbitmq.conf
cat advanced.config
cat definitions.json
```

### 3.5 Update Network Configuration

```bash
# Update /etc/hosts on ALL nodes
./environment-manager.sh update-hosts prod

# Or manually update /etc/hosts on each node:
sudo tee -a /etc/hosts << EOF
# RabbitMQ Cluster - prod Environment  
10.20.20.10 prod-rmq-node1
10.20.20.11 prod-rmq-node2
10.20.20.12 prod-rmq-node3
EOF
```

## 4. Cluster Deployment

### 4.1 Deploy Configuration Files to All Nodes

```bash
# Copy deployment directory to all nodes
scp -r /opt/rabbitmq-deployment/ root@prod-rmq-node1:/opt/
scp -r /opt/rabbitmq-deployment/ root@prod-rmq-node2:/opt/
scp -r /opt/rabbitmq-deployment/ root@prod-rmq-node3:/opt/

# Alternative: Use environment manager to deploy configs
./environment-manager.sh deploy prod
```

### 4.2 Setup Primary Node (Node 1)

```bash
# On prod-rmq-node1:
cd /opt/rabbitmq-deployment

# Setup as primary node
./cluster-setup-environment.sh -e prod -r primary

# Expected output:
# ✅ Environment loaded: prod (production)
# ✅ Primary node setup completed
# ✅ Cluster operational: 1/3 nodes running
```

### 4.3 Setup Secondary Nodes

```bash
# On prod-rmq-node2:
cd /opt/rabbitmq-deployment
./cluster-setup-environment.sh -e prod -r secondary

# On prod-rmq-node3:
cd /opt/rabbitmq-deployment  
./cluster-setup-environment.sh -e prod -r secondary

# Expected output on each:
# ✅ Successfully joined cluster
# ✅ Secondary node setup completed
```

### 4.4 Verify Cluster Formation

```bash
# On any node, check cluster status:
sudo rabbitmqctl cluster_status

# Expected output:
# Cluster status of node rabbit@prod-rmq-node1 ...
# Basics
# Cluster name: rabbitmq-prod-cluster
# Disk Nodes: [rabbit@prod-rmq-node1, rabbit@prod-rmq-node2, rabbit@prod-rmq-node3]
# Running Nodes: [rabbit@prod-rmq-node1, rabbit@prod-rmq-node2, rabbit@prod-rmq-node3]

# Verify cluster name
sudo rabbitmqctl eval 'rabbit_nodes:cluster_name().'
# Expected: <<"rabbitmq-prod-cluster">>

# Check node health
sudo rabbitmqctl node_health_check
# Expected: Health check passed

# List users
sudo rabbitmqctl list_users
# Expected: admin, teja, aswini users present
```

## 5. Auto-Recovery Setup

### 5.1 Enhanced Systemd Service (Run on ALL nodes)

```bash
# Install enhanced systemd service with auto-recovery
sudo cp systemd-service-template.service /etc/systemd/system/rabbitmq-server@.service

# Update service to use environment
sudo sed -i "s/%i/prod/g" /etc/systemd/system/rabbitmq-server@.service

# Reload systemd and enable service
sudo systemctl daemon-reload
sudo systemctl disable rabbitmq-server
sudo systemctl enable rabbitmq-server@prod.service
sudo systemctl restart rabbitmq-server@prod.service

# Verify service status
sudo systemctl status rabbitmq-server@prod.service
```

### 5.2 Setup Auto-Recovery Monitor

```bash
# On primary node, start auto-recovery monitor
./cluster-auto-recovery-monitor.sh -e prod -d -l /var/log/rabbitmq-auto-recovery.log

# Verify monitor is running
ps aux | grep cluster-auto-recovery-monitor
cat /var/log/rabbitmq-auto-recovery.log

# Expected output:
# ✅ Cluster Auto-Recovery Monitor Started
# ℹ Environment: prod (production)
# ℹ Check Interval: 30s
```

### 5.3 Test Auto-Recovery

```bash
# Test 1: Single node restart (should continue operating)
sudo systemctl restart rabbitmq-server@prod.service  # On one node
./monitor-environment.sh -e prod -m once
# Expected: ✅ Cluster operational: 3/3 nodes running

# Test 2: Simulate complete failure (controlled test)
# Stop all nodes simultaneously
sudo systemctl stop rabbitmq-server@prod.service  # On all nodes

# Wait and check auto-recovery
sleep 180
./monitor-environment.sh -e prod -m once
# Expected: Auto-recovery should have triggered
```

## 6. SSL/TLS Configuration (Optional but Recommended)

### 6.1 Generate SSL Certificates

```bash
# Create SSL directory for environment
sudo mkdir -p /etc/rabbitmq/ssl/prod

# Generate CA certificate
sudo openssl genrsa -out /etc/rabbitmq/ssl/prod/ca_key.pem 4096
sudo openssl req -new -x509 -days 3650 -key /etc/rabbitmq/ssl/prod/ca_key.pem -out /etc/rabbitmq/ssl/prod/ca_certificate.pem -subj "/CN=RabbitMQ-Prod-CA"

# Generate server certificates for each node
for node in prod-rmq-node1 prod-rmq-node2 prod-rmq-node3; do
    sudo openssl genrsa -out /etc/rabbitmq/ssl/prod/${node}_key.pem 4096
    sudo openssl req -new -key /etc/rabbitmq/ssl/prod/${node}_key.pem -out /etc/rabbitmq/ssl/prod/${node}.csr -subj "/CN=$node"
    sudo openssl x509 -req -days 3650 -in /etc/rabbitmq/ssl/prod/${node}.csr -CA /etc/rabbitmq/ssl/prod/ca_certificate.pem -CAkey /etc/rabbitmq/ssl/prod/ca_key.pem -CAcreateserial -out /etc/rabbitmq/ssl/prod/${node}_certificate.pem
done

# Set permissions
sudo chown -R rabbitmq:rabbitmq /etc/rabbitmq/ssl
sudo chmod 600 /etc/rabbitmq/ssl/prod/*_key.pem
sudo chmod 644 /etc/rabbitmq/ssl/prod/*_certificate.pem /etc/rabbitmq/ssl/prod/ca_certificate.pem

# Copy certificates to all nodes
for node in prod-rmq-node2 prod-rmq-node3; do
    scp -r /etc/rabbitmq/ssl/ root@$node:/etc/rabbitmq/
done
```

### 6.2 Enable SSL in Environment

```bash
# Update environment configuration
sed -i 's/RABBITMQ_SSL_ENABLED="false"/RABBITMQ_SSL_ENABLED="true"/' environments/prod.env

# Regenerate configurations with SSL
./generate-configs.sh prod

# Deploy updated configurations
./environment-manager.sh deploy prod

# Restart cluster to apply SSL
./rolling-restart-environment.sh -e prod
```

## 7. Operational Procedures

### 7.1 Interactive Operations Dashboard

```bash
# Access comprehensive operations menu
./environment-operations.sh operations-menu prod

# Dashboard provides:
# 📊 Real-time environment status
# 🔍 Health checks and monitoring
# 🔄 Rolling restart management
# ⚙️ Configuration management
# 💾 Backup and restore operations
```

### 7.2 Environment Dashboard

```bash
# Show environment dashboard
./environment-operations.sh dashboard prod

# Expected output:
# ╔════════════════════════════════════════════════════════════════╗
# ║               RabbitMQ Environment Dashboard                   ║
# ╚════════════════════════════════════════════════════════════════╝
# 
# Environment: prod (production)
# Cluster: rabbitmq-prod-cluster
# 
# === Cluster Nodes ===
# Node 1: prod-rmq-node1 (10.20.20.10) ✅ Running (Local)
# Node 2: prod-rmq-node2 (10.20.20.11) ✅ Running  
# Node 3: prod-rmq-node3 (10.20.20.12) ✅ Running
```

### 7.3 Health Monitoring

```bash
# Comprehensive health check
./environment-operations.sh health-check prod

# Continuous monitoring
./monitor-environment.sh -e prod -m continuous -i 30

# Monitor with JSON output for automation
./monitor-environment.sh -e prod -f json

# Monitor with Prometheus metrics
./monitor-environment.sh -e prod -f prometheus
```

### 7.4 Queue Management

```bash
# Create environment-specific queues
./create-environment-queues.sh prod

# List all queues
sudo rabbitmqctl list_queues name messages consumers type

# Create custom queues
sudo rabbitmqctl declare queue --name=orders --type=quorum --durable=true
sudo rabbitmqctl declare queue --name=payments --type=quorum --durable=true
sudo rabbitmqctl declare queue --name=notifications --type=quorum --durable=true

# Verify queue distribution
sudo rabbitmqctl list_queues name type online_members members
```

## 8. Cluster Recovery Procedures

### 8.1 Single Node Failure Recovery

```bash
# Scenario: One node goes down
# Expected: Cluster continues operating with 2/3 nodes

# Check cluster status
sudo rabbitmqctl cluster_status
# Should show 2 running nodes

# Restart failed node
ssh root@failed-node "systemctl restart rabbitmq-server@prod.service"

# Verify node rejoins
sleep 30
sudo rabbitmqctl cluster_status
# Should show 3 running nodes
```

### 8.2 Two Node Failure Recovery

```bash
# Scenario: Two nodes go down (minority partition)
# Expected: Remaining node pauses operations (pause_minority behavior)

# Check cluster status
sudo rabbitmqctl cluster_status
# May not respond (node paused in minority)

# Check service status
sudo systemctl status rabbitmq-server@prod.service
# Should show: Active: active (running)

# Start one additional node to restore majority
ssh root@node2 "systemctl start rabbitmq-server@prod.service"

# Wait for recovery
sleep 60
sudo rabbitmqctl cluster_status
# Should show cluster operational again
```

### 8.3 Complete Cluster Failure Recovery

```bash
# Scenario: All nodes go down (power outage, etc.)
# Solution: Use auto-recovery system

# Method 1: Automatic recovery (if auto-recovery monitor is running)
# - Monitor detects failure after 5 consecutive checks
# - Automatically triggers force boot recovery
# - Sends alerts to operations team

# Method 2: Manual force boot recovery
./auto-force-boot.sh -e prod

# Expected output:
# ⚠ Cluster not responding, initiating recovery process...
# ⚠ Force booting cluster...
# ✅ Force boot successful, cluster recovered!
# 📡 Notifying other nodes to rejoin...
# ✅ All nodes successfully rejoined cluster

# Method 3: Controlled recovery with specific boot order
./managed-cluster-boot.sh -e prod -m force

# Verify recovery
sudo rabbitmqctl cluster_status
./environment-operations.sh health-check prod
```

### 8.4 Network Partition Recovery

```bash
# Scenario: Network partition splits cluster
# Check partition status
sudo rabbitmqctl eval 'rabbit_node_monitor:partitions().'

# For autoheal configuration (QA/Staging):
# - Partitions automatically heal when network recovers

# For pause_minority configuration (Production):
# - Minority partition pauses operations
# - Majority partition continues operating
# - When network heals, paused nodes rejoin automatically

# Manual partition recovery if needed:
sudo rabbitmqctl forget_cluster_node rabbit@isolated-node
# Then restart the isolated node to rejoin
```

## 9. Maintenance Operations

### 9.1 Rolling Restart

```bash
# Environment-aware rolling restart
./rolling-restart-environment.sh -e prod

# Rolling restart with custom wait time
./rolling-restart-environment.sh -e prod -w 60

# Force rolling restart without prompts
./rolling-restart-environment.sh -e prod -f

# Expected process:
# 1. Pre-restart validation
# 2. Restart secondary nodes first
# 3. Restart primary node last  
# 4. Post-restart validation
# 5. Verify all nodes healthy
```

### 9.2 Configuration Updates

```bash
# Update environment configuration
vi environments/prod.env

# Validate changes
./load-environment.sh validate prod

# Generate new configurations
./generate-configs.sh prod

# Deploy via rolling restart
./rolling-restart-environment.sh -e prod

# Verify changes applied
./environment-operations.sh dashboard prod
```

### 9.3 Backup and Restore

```bash
# Create environment backup
./environment-manager.sh backup prod

# Manual backup
BACKUP_DIR="/backup/rabbitmq-$(date +%Y%m%d-%H%M%S)"
sudo mkdir -p "$BACKUP_DIR"
sudo rabbitmqctl export_definitions "$BACKUP_DIR/definitions.json"
sudo cp -r /etc/rabbitmq "$BACKUP_DIR/"
sudo cp -r /var/lib/rabbitmq "$BACKUP_DIR/"

# Restore from backup (if needed)
sudo rabbitmqctl import_definitions "$BACKUP_DIR/definitions.json"
```

### 9.4 User Management

```bash
# Add new user
sudo rabbitmqctl add_user newuser password123
sudo rabbitmqctl set_user_tags newuser management
sudo rabbitmqctl set_permissions -p / newuser ".*" ".*" ".*"

# Update user password
sudo rabbitmqctl change_password teja NewPassword456!

# List users and permissions
sudo rabbitmqctl list_users
sudo rabbitmqctl list_permissions -p /
```

## 10. Monitoring and Alerting

### 10.1 Setup Continuous Monitoring

```bash
# Start monitoring daemon
./cluster-auto-recovery-monitor.sh -e prod -d -l /var/log/rabbitmq-monitor.log

# Configure monitoring with alerts
# Update environments/prod.env:
EMAIL_ALERTS="ops-team@company.com,cto@company.com"
SLACK_WEBHOOK="https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK"

# Start monitoring with alerting
./monitor-environment.sh -e prod -m daemon -a
```

### 10.2 Prometheus Integration

```bash
# Enable Prometheus plugin
sudo rabbitmq-plugins enable rabbitmq_prometheus

# Configure Prometheus scraping
# Add to prometheus.yml:
# - job_name: 'rabbitmq-prod'
#   static_configs:
#     - targets: ['prod-rmq-node1:15692', 'prod-rmq-node2:15692', 'prod-rmq-node3:15692']

# Monitor with Prometheus output
./monitor-environment.sh -e prod -f prometheus
```

### 10.3 Log Monitoring

```bash
# Monitor RabbitMQ logs
sudo tail -f /var/log/rabbitmq/rabbit@$(hostname).log

# Monitor auto-recovery logs
tail -f /var/log/rabbitmq-auto-recovery.log

# Monitor system logs
sudo journalctl -u rabbitmq-server@prod.service -f
```

## 11. Performance Tuning

### 11.1 OS-Level Tuning

```bash
# Increase file descriptor limits
echo 'rabbitmq soft nofile 65536' | sudo tee -a /etc/security/limits.conf
echo 'rabbitmq hard nofile 65536' | sudo tee -a /etc/security/limits.conf

# Optimize network settings
echo 'net.core.rmem_default = 262144' | sudo tee -a /etc/sysctl.conf
echo 'net.core.rmem_max = 16777216' | sudo tee -a /etc/sysctl.conf
echo 'net.core.wmem_default = 262144' | sudo tee -a /etc/sysctl.conf
echo 'net.core.wmem_max = 16777216' | sudo tee -a /etc/sysctl.conf
sudo sysctl -p

# Disable swap for better performance
sudo swapoff -a
```

### 11.2 RabbitMQ Performance Settings

```bash
# Update environment configuration for production
# In environments/prod.env:
RABBITMQ_VM_MEMORY_HIGH_WATERMARK="0.7"
RABBITMQ_DISK_FREE_LIMIT="5GB"
RABBITMQ_HEARTBEAT="60"
RABBITMQ_FRAME_MAX="131072"
RABBITMQ_CHANNEL_MAX="2047"

# Apply changes
./generate-configs.sh prod
./rolling-restart-environment.sh -e prod
```

## 12. Load Balancer Configuration

### 12.1 HAProxy Setup

```bash
# Generate HAProxy configuration
./setup-haproxy-for-rolling-restarts.sh

# Deploy HAProxy configuration
scp /tmp/haproxy-rabbitmq.cfg root@haproxy-server:/etc/haproxy/
ssh root@haproxy-server "systemctl restart haproxy"

# Test load balancer
curl -u admin:password http://rabbitmq-vip:15672/api/overview
```

### 12.2 Load Balancer Health Checks

```bash
# Configure health check endpoints
# HAProxy will automatically remove unhealthy nodes
# and add them back when they recover

# Monitor load balancer status
curl http://haproxy-server:8080/stats
```

## 13. Security Hardening

### 13.1 SSL/TLS Hardening

```bash
# Update SSL configuration for production
# In generated rabbitmq.conf:
ssl_options.versions.1 = tlsv1.2
ssl_options.versions.2 = tlsv1.3
ssl_options.ciphers.1 = ECDHE-RSA-AES256-GCM-SHA384
ssl_options.honor_cipher_order = true
ssl_options.honor_ecc_order = true

# Apply SSL hardening
./generate-configs.sh prod
./rolling-restart-environment.sh -e prod
```

### 13.2 User Security

```bash
# Remove default guest user (already done by scripts)
sudo rabbitmqctl delete_user guest

# Set strong password policy
# Use complex passwords for all users
# Regularly rotate passwords

# Audit user access
sudo rabbitmqctl list_users
sudo rabbitmqctl list_permissions -p /
```

## 14. Troubleshooting Guide

### 14.1 Common Issues and Solutions

#### Issue: Cluster formation fails
```bash
# Check Erlang cookie consistency
sudo cat /var/lib/rabbitmq/.erlang.cookie  # Should be same on all nodes

# Check network connectivity
ping prod-rmq-node2
ssh root@prod-rmq-node2 "rabbitmqctl ping"

# Check firewall
sudo firewall-cmd --list-ports
```

#### Issue: Node health check fails
```bash
# Check disk space
df -h

# Check memory usage
free -h

# Check logs
sudo tail -50 /var/log/rabbitmq/rabbit@$(hostname).log
```

#### Issue: Auto-recovery not working
```bash
# Check monitor status
ps aux | grep cluster-auto-recovery-monitor

# Check monitor logs
tail -f /var/log/rabbitmq-auto-recovery.log

# Restart monitor
./cluster-auto-recovery-monitor.sh -e prod -d
```

### 14.2 Debug Commands

```bash
# Comprehensive cluster diagnostics
sudo rabbitmq-diagnostics status
sudo rabbitmq-diagnostics cluster_status
sudo rabbitmq-diagnostics check_running
sudo rabbitmq-diagnostics check_local_alarms

# Network diagnostics
sudo rabbitmq-diagnostics check_port_connectivity
sudo rabbitmq-diagnostics ping rabbit@prod-rmq-node2

# Performance diagnostics
sudo rabbitmq-diagnostics memory_breakdown
sudo rabbitmq-diagnostics runtime_thread_stats
```

## 15. Production Deployment Checklist

### 15.1 Pre-Deployment Checklist

- [ ] **Infrastructure Ready**
  - [ ] All nodes provisioned with correct specs
  - [ ] Network connectivity verified
  - [ ] Firewall rules configured
  - [ ] DNS/hostnames configured
  - [ ] NTP synchronized across all nodes

- [ ] **Software Installation**
  - [ ] RHEL 8.x installed and updated
  - [ ] Erlang 26.x installed
  - [ ] RabbitMQ 4.1.x installed
  - [ ] Deployment scripts downloaded

- [ ] **Configuration**
  - [ ] Environment configuration file updated
  - [ ] Configuration validated
  - [ ] SSL certificates generated (if using SSL)
  - [ ] User credentials configured

### 15.2 Deployment Checklist

- [ ] **Cluster Setup**
  - [ ] Primary node configured and started
  - [ ] Secondary nodes joined cluster
  - [ ] Cluster status verified
  - [ ] Cluster name verified
  - [ ] All nodes healthy

- [ ] **Auto-Recovery Setup**
  - [ ] Enhanced systemd service deployed
  - [ ] Auto-recovery monitor started
  - [ ] Auto-recovery tested
  - [ ] Monitoring configured

- [ ] **Operational Verification**
  - [ ] Management UI accessible
  - [ ] Users can authenticate
  - [ ] Queues can be created
  - [ ] Messages can be published/consumed
  - [ ] SSL working (if enabled)

### 15.3 Post-Deployment Checklist

- [ ] **Monitoring Setup**
  - [ ] Auto-recovery monitor running
  - [ ] Prometheus metrics configured
  - [ ] Alerting configured
  - [ ] Dashboard accessible

- [ ] **Load Balancer**
  - [ ] HAProxy configured
  - [ ] Health checks working
  - [ ] VIP accessible

- [ ] **Documentation**
  - [ ] Environment configuration documented
  - [ ] Access credentials provided to team
  - [ ] Operational procedures documented
  - [ ] Emergency contacts configured

- [ ] **Testing**
  - [ ] Single node failure tested
  - [ ] Rolling restart tested
  - [ ] Complete recovery tested
  - [ ] Performance tested
  - [ ] Security tested

## 16. Quick Reference Commands

### Environment Management
```bash
# Load environment
source ./load-environment.sh prod

# Show environment status
./environment-operations.sh dashboard prod

# Interactive operations menu
./environment-operations.sh operations-menu prod
```

### Cluster Operations
```bash
# Check cluster status
sudo rabbitmqctl cluster_status

# Health check
./environment-operations.sh health-check prod

# Rolling restart
./rolling-restart-environment.sh -e prod
```

### Recovery Operations
```bash
# Force boot recovery
./auto-force-boot.sh -e prod

# Start auto-recovery monitor
./cluster-auto-recovery-monitor.sh -e prod -d

# Monitor cluster
./monitor-environment.sh -e prod -m continuous
```

### Management Operations
```bash
# List queues
sudo rabbitmqctl list_queues name messages consumers

# List users
sudo rabbitmqctl list_users

# Export definitions
sudo rabbitmqctl export_definitions /tmp/definitions.json
```

## 🎉 Conclusion

You now have a complete, production-ready RabbitMQ 4.1.x deployment with:

✅ **Environment-based configuration** with static cluster names  
✅ **Complete auto-recovery** for power outages and server reboots  
✅ **Comprehensive monitoring** and alerting  
✅ **Production-grade security** and operational procedures  
✅ **Detailed troubleshooting** and maintenance guides  

Your RabbitMQ cluster is ready for production deployment with automatic recovery from any failure scenario!